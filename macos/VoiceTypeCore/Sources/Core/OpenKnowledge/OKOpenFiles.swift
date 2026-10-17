import Darwin
import Foundation

/// Whether a file taken out of a destination can still change. Whoever had
/// the destination open keeps writing to the same inode through that
/// descriptor or a writable mapping, so such a file is only deleted once no
/// process can write it: after that, only its staging path reaches it.
enum OKOpenFiles {
    /// True only when `url` is a regular file with a single link and no
    /// process of this user holds it in a way that can write: a descriptor
    /// opened for writing, or a mapping whose maximum protection allows
    /// writing. A read-only descriptor can never write, so it doesn't count.
    /// When a process can't be read, or keeps changing while it's read, the
    /// answer is false. This process counts too. Processes of other users
    /// can't be read without root and aren't counted.
    static func isReleased(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { return false }
        let file = Inode(device: UInt32(bitPattern: info.st_dev), number: UInt64(info.st_ino))
        guard describesToUs(url, file) else { return false }
        // A process started during the scan could have inherited a
        // descriptor from one already scanned: scan until no new one shows up.
        var scanned = Set<pid_t>()
        for _ in 0..<10 {
            guard let pids = processesOfThisUser() else { return false }
            let new = pids.subtracting(scanned)
            if new.isEmpty { return true }
            for pid in new {
                guard canWrite(pid, file) == false else { return false }
                scanned.insert(pid)
            }
        }
        return false
    }

    private struct Inode: Equatable {
        var device: UInt32
        var number: UInt64
    }

    /// The kernel decides whether it describes a descriptor to us from our
    /// credentials and the vnode alone. It describes one of our own on this
    /// file, so a descriptor elsewhere it refuses to describe (`EPERM`, a
    /// file we may not look at) isn't this file. Our read-only descriptor
    /// is closed before the scan, and couldn't write anyway.
    private static func describesToUs(_ url: URL, _ file: Inode) -> Bool {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var vnode = vnode_fdinfowithpath()
        guard proc_pidfdinfo(getpid(), fd, PROC_PIDFDVNODEPATHINFO, &vnode, Int32(MemoryLayout<vnode_fdinfowithpath>.size)) > 0 else { return false }
        let stat = vnode.pvip.vip_vi.vi_stat
        return stat.vst_dev == file.device && stat.vst_ino == file.number
    }

    /// The live (non-zombie) processes of this user; nil when the list
    /// can't be read.
    private static func processesOfThisUser() -> Set<pid_t>? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return nil }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 64)
        size = procs.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return nil }
        return Set(procs.prefix(size / MemoryLayout<kinfo_proc>.stride)
            .filter { $0.kp_proc.p_stat != SZOMB }
            .map(\.kp_proc.p_pid))
    }

    /// nil when `pid` can't be read.
    private static func canWrite(_ pid: pid_t, _ file: Inode) -> Bool? {
        guard let descriptors = writableDescriptor(pid, file) else { return nil }
        if descriptors { return true }
        return writableMapping(pid, file)
    }

    /// Reads each descriptor, then lists them again and reads the numbers
    /// not read yet, until a list brings none: a descriptor moved to a new
    /// number while the list was read shows up there. One that closed
    /// before it was read (`EBADF`) is read again if its number comes back.
    /// A descriptor the kernel won't describe (`EPERM`, see `describesToUs`)
    /// or that was revoked (`ENOENT`, a dead vnode) isn't this file.
    private static func writableDescriptor(_ pid: pid_t, _ file: Inode) -> Bool? {
        var read = Set<Int32>()
        for _ in 0..<20 {
            guard let fds = descriptors(pid) else { return nil }
            let unread = fds.filter { !read.contains($0.proc_fd) }
            if unread.isEmpty { return false }
            for fd in unread {
                read.insert(fd.proc_fd)
                guard fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) else { continue }
                var vnode = vnode_fdinfowithpath()
                errno = 0
                if proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &vnode, Int32(MemoryLayout<vnode_fdinfowithpath>.size)) <= 0 {
                    let code = errno
                    if code == ESRCH { return false }
                    if code == EPERM || code == ENOENT { continue }
                    guard code == EBADF else { return nil }
                    read.remove(fd.proc_fd)
                    continue
                }
                let stat = vnode.pvip.vip_vi.vi_stat
                if stat.vst_dev == file.device, stat.vst_ino == file.number, vnode.pfi.fi_openflags & UInt32(FWRITE) != 0 {
                    return true
                }
            }
        }
        return nil
    }

    /// Empty for a process that exited; nil when the list can't be read.
    private static func descriptors(_ pid: pid_t) -> [proc_fdinfo]? {
        let stride = MemoryLayout<proc_fdinfo>.stride
        errno = 0
        let needed = Int(proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0))
        if needed <= 0, errno == ESRCH { return [] }
        guard needed > 0 || errno == 0 else { return nil }
        // Room for descriptors opened in the meantime; a full buffer may
        // have left some out, so it's tried again bigger.
        var capacity = needed / stride + 64
        for _ in 0..<5 {
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
            errno = 0
            let bytes = Int(proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(capacity * stride)))
            if bytes <= 0, errno == ESRCH { return [] }
            guard bytes > 0 || errno == 0 else { return nil }
            if bytes / stride < capacity { return Array(fds.prefix(bytes / stride)) }
            capacity *= 2
        }
        return nil
    }

    /// Walks the process's file-backed regions (`PROC_PIDREGIONPATHINFO2`,
    /// which skips anonymous memory). The walk ends with `EINVAL`; since a
    /// live process always maps its executable, `EINVAL` on the first call
    /// means the kernel doesn't support it, and the process can't be read.
    private static func writableMapping(_ pid: pid_t, _ file: Inode) -> Bool? {
        let fileBackedRegions: Int32 = 22 // PROC_PIDREGIONPATHINFO2, not in the SDK headers
        var address: UInt64 = 0
        var first = true
        while true {
            var region = proc_regionwithpathinfo()
            errno = 0
            if proc_pidinfo(pid, fileBackedRegions, address, &region, Int32(MemoryLayout<proc_regionwithpathinfo>.size)) <= 0 {
                let code = errno
                if code == ESRCH { return false }
                return code == EINVAL && !first ? false : nil
            }
            first = false
            let stat = region.prp_vip.vip_vi.vi_stat
            if stat.vst_dev == file.device, stat.vst_ino == file.number,
               region.prp_prinfo.pri_max_protection & UInt32(VM_PROT_WRITE) != 0 {
                return true
            }
            let next = region.prp_prinfo.pri_address + region.prp_prinfo.pri_size
            guard next > address else { return nil }
            address = next
        }
    }
}
