# Biometric Keychain

```
Usage:
    get    <namespace> <key>
    set    <namespace> <key> <value> [strict]
    delete <namespace> <key> [strict]

Arguments:
    <namespace> A unique value used to prevent storage conflicts.
    <key>       The key to operate on.
    <value>     The value to store (only for 'set').
    strict      Optional boolean flag (true/false). Defaults to false.
                 - For 'set': If the key already exists, the command will fail.
                 - For 'delete': If the key does not exist, the command will fail.

Examples:
    set    namespace key value
    set    namespace key value true
    get    namespace key
    delete namespace key
    delete namespace key true
```

<!-- Alternatively, use `swift test.swift` instead. -->

![Screenshot of Script in Terminal](https://github.com/user-attachments/assets/858aca53-8bb3-4421-adaf-867ae4aff9ae)

<!-- ![Screenshot of Script in Terminal](https://github.com/user-attachments/assets/21ef6575-de5e-4434-80c9-3f670ca7ae7b) -->

> [!TIP]
> Run `chmod +x main.swift` to fix `zsh: permission denied: ./main.swift` error.
