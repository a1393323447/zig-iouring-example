# Introduction
This git repository contains several examples about using `io_uring` in `Zig`. These examples are based on the article series [Lord of the io_uring](https://unixism.net/loti/index.html).

# Build and Run
Build an app with `zig build -Dapp=APP_NAME`. 

Run an app with `zig build run -Dapp=APP_NAME`. 

Run an app with args, you should use `zig build run -Dapp=APP_NAME -- args`.

# Available apps
Now the following apps are available:
- cat
- cp
- probe
- linking_requests

You can find their source code in the `src` directory.
