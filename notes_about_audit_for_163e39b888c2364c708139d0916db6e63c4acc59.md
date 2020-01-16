# Notes about audit report

# Summary

This document includes notes about [TheWall Security Audit Report](https://gist.github.com/yuriy77k/6d8003568464182ed097d97950a355d5) performed by [Callisto Security Audit Department](https://github.com/EthereumCommonwealth/Auditing)

# Detailes

## Multiple Areas at the same coordinates (3.1)

Fixed. Changed order in create() member.

## Premium Pre-computing (3.2)

Implemented three-steps procedure for random values creation. On the first step administrator create secret S, calculate H=keccak256(S) and load it into contract using updateSecret(H) member. All new created areas will have association to H and own nonce, which can be added by user as parameter of create() and createMulti() members to avoid of manupulation from administrators.

On the second step administrator create new secret S_new, calculate H_new=keccak256(S_new) and do updateSecter(H_new). We need to update hash before opening our old secret to avoid manupulations from side of miners. Since this moment all new created areas will have association to H_new.

On the third step we need to open secret S. It can be done using commitSecret() member. Since this moment all areas, which was associated with H, will have determidet premium status.

## Cluster Size (3.3)

It is impossible to limit number of areas to be added in a cluster, because we can't initially know exactly how much gas do we need. Current implementation allows us to manage clusters of every size, includes very large clusters, because we have _removeFromCluster() member. If you learn this member carefully, you can see that not every call requires full loop. If user will remove areas from cluster using FIFO logic, gas consumption will be constant and low-valued.

## Delegate Call (3.4)

Fixed. Removed all delegate calls from all contracts.

## Delegate Call Return Value (3.5)

Fixed. Removed all delegate calls from all contracts.

## Zero Address Check (3.6)

Fixed. Added conditions for non-zero values.

## Wall Size (3.7)

Fixed. Added conditions.

## Area Creation (3.8)

Fixed. It is not possible to call _create() member by admins.

## ERC223 Compliance (Burn Logic) (3.9)

Sure, it is possible to implement more common logic in part of interaction between TheWallUsers and TheWallCoupons contracts using tokenFallback() member, but it will be not so convinient for end-users, because one-step logic becomes two-three steps for them.

Fixed. No more allowed to call _burn() member by admins, can be called from TheWallUsers contract only, which guarantees, that source of call is user with permission.

## Owner privileges (3.10)

Fixed. It is not possible to call internal members by admins and not possible to change address of coupons countract.
