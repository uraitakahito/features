# Architecture Decision Record

1. The `features` project is primarily used only in development environments.
2. We want to avoid issues caused by differences between `musl` and `glibc`.
3. For example, many parts in `origin` do not support Alpine Linux, such as [src/node](src/node).

For these three reasons, we have decided to exclude Alpine Linux from the supported environments for `features`.
