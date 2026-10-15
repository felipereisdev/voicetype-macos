# Third-party assets

## recording_start.wav

Source: Sotto by Evert Junior
License: MIT

Copy: `macos/VoiceType/Resources/recording_start.wav`

```
MIT License

Copyright (c) 2026 Evert Junior

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## FluidAudio

Source: https://github.com/FluidInference/FluidAudio (v0.17.7, Swift package)
License: Apache-2.0

Used for on-device speaker diarization of the meeting system track. Its Core ML
models (pyannote segmentation + WeSpeaker embeddings) are downloaded at runtime
from Hugging Face (FluidInference/speaker-diarization-coreml) under their own
CC-BY-4.0 terms; they are not bundled in this repository.
