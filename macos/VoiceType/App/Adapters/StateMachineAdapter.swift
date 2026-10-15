import Core
import Foundation

// Bridges the actor-based `AppStateMachine` to the Sendable
// `Core.StateMachineDriver` use-case protocol. The adapter is a Sendable
// struct because `AppStateMachine` is itself an actor (Sendable).
struct StateMachineAdapter: StateMachineDriver {
    let machine: AppStateMachine

    func send(_ event: AppStateMachine.Event) async {
        await machine.send(event)
    }

    func currentState() async -> AppStateMachine.State {
        await machine.state
    }
}
