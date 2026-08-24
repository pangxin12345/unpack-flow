# Security Policy

Do not publish credentials, private data, exploit details, or sensitive server paths in a public issue.

Maintainer: [once-email.com](https://once-email.com)

Creator and developer: helen.jar. GitHub project: [pangxin12345/unpack-flow](https://github.com/pangxin12345/unpack-flow).

For security reports, email [tiantuowl@gmail.com](mailto:tiantuowl@gmail.com) with the affected version, impact, and safe reproduction details. Do not include credentials, private archives or sensitive logs.

UnpackFlow 2.1.7 and later enumerate archive entries before each first-level or recursive extraction. Absolute paths, normalized paths that escape the selected destination, and archive link entries are rejected before an extraction engine is allowed to write files.
