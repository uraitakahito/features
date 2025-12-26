# Architecture Decision Record

1. The `features` project is primarily used only in development environments.
2. We want to avoid issues caused by differences between `musl` and `glibc`.

For these two reasons, we have decided to exclude Alpine Linux from the supported environments for `features`.
