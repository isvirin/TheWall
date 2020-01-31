# Notes about audit report

# Summary

This document includes notes about [TheWall Security Audit Report](https://gist.github.com/yuriy77k/4bd91115389406a43889021f4a86be09) performed by [Callisto Security Audit Department](https://github.com/EthereumCommonwealth/Auditing)

# Detailes

## Cluster Size (3.1)

We have used another structure for storing areas inside cluster: add mapping of areaId to index of this area in array. It makes possible to avoid loops in removeFromCluster() member, which works for constant time now.

We have removed all loops from transfer functions family. We actually don't transfer tokens of areas, when transfer cluster. We transfer areas only when we remove area from cluster or remove cluster at all.

We have long loop in removeCluster() member only. It is not dangerous and not inconvinient for users. This is quite rare operation and if user faces to problem with incufficient gas, he can remove some areas from cluster before removing cluster.

## Premium Computing (3.2)

Investors and customers are informed about this owner privileges.

## Owner privileges (3.3)

Investors and customers are informed about this owner privileges.
