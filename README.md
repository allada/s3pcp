# s3pcp - s3 parallel copy
This tool will use `aws-cli` and `pjoin` utility to download a file very fast and efficient in parallel. This is accomplished by querying s3 for all of the "parts" of the s3 object and downloading each part separate and buffering the results then piping all the data back together into one output stream.

Running this tool as: `s3pcp s3://{bucket}/{key}` is functionally identical to `aws s3 cp s3://{bucket}/{key} -`, but should download significantly faster because it parallelizes much more efficiently.

## Installation
You need to have the [pjoin](https://github.com/allada/putils/tree/master/pjoin)` utility installed. This can be done automatically using
```
sudo -E env "PATH=$PATH" make s3pcp
```

## License
Copyright 2022 Nathan (Blaise) Bruer

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
