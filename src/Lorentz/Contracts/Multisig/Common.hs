{-# LANGUAGE RebindableSyntax #-}
{-# OPTIONS_GHC -Wno-orphans #-}
module Lorentz.Contracts.Multisig.Common
  ( updateNonceIfCorrect
  , checkSignatures
  , ensureQuorum
  , ensureKeyEligible
  ) where

import Lorentz

import Lorentz.Contracts.Multisig.Error ()
import Lorentz.Contracts.Multisig.Parameter
import Lorentz.Contracts.Multisig.Storage

-- | Ensures nonce is equal to (currentNonce + 1) and updates currentNonce
-- if the condition holds. Otherwise, fails with #invalidNonce
updateNonceIfCorrect :: forall s. Parameter ': Storage ': s :-> Storage ': s
updateNonceIfCorrect = do
  dip $ do
    getField #currentNonce
    push @Natural 1
    add
    dup
  toField #nonce
  if IsEq
  then setField #currentNonce
  else failCustom_ #invalidNonce

-- | Ensures that there's enough signatures, checks each of the supplied
-- signatures, fails if the quorum is not met or if any of the signatures
-- is invalid.
checkSignatures :: forall s. Parameter ': Storage ': s :-> s
checkSignatures = do
  dup; packParameter

  swap; toField #signatures
  dipN @2 $ toField #teamKeys

  stackType @(Signatures : ByteString : Set KeyHash : s)
  map $ do
    unpair;
    stackType @(PublicKey : TSignature ByteString : ByteString : Set KeyHash : s)
    duupX @4; duupX @2; ensureKeyEligible
    dipN @2 dup; dup ; dip ensureSignatureValid; hashKey

  stackType @([KeyHash] : ByteString : Set KeyHash : s)
  dip drop
  listToSet
  toNamed #supplied
  dip $ toNamed #eligible
  ensureQuorum

ensureQuorum :: ("supplied" :! Set KeyHash) ': ("eligible" :! Set KeyHash) ': s1 :-> s1
ensureQuorum = do
  dip $ do
    fromNamed #eligible
    size
  fromNamed #supplied
  size
  push @Natural 2
  mul  -- 2 * supplied signatures > eligible keys count,
  gt   -- note the strict inequality
  if Holds
  then nop
  else failCustom_ #majorityQuorumNotReached

packParameter :: Parameter : s1 :-> ByteString : s1
packParameter = do
  constructT @ValueToSign $
    ( fieldCtor $ self @Parameter # address
    , fieldCtor $ getField #nonce
    , fieldCtor $ getField #order
    )
  dip drop
  stackType @(ValueToSign : _)
  packRaw

ensureKeyEligible :: PublicKey : Set KeyHash : s1 :-> s1
ensureKeyEligible = do
  dup; hashKey
  dip swap
  mem
  if Holds
  then drop
  else failCustom #invalidSignature

-- | Converts a list of comparable values to a set,
-- removes duplicates as a consequence.
listToSet
  :: forall a s. (NiceComparable a)
  => ((List a) : s) :-> ((Set a) : s)
listToSet = do
  dip (emptySet @a);
  iter (do dip (push True); update)

type instance ErrorArg "invalidSignature" = PublicKey
instance (CustomErrorHasDoc "invalidSignature") where
  customErrClass = ErrClassActionException
  customErrDocMdCause =
    "At least one of the supplied signatures was invalid"
  customErrArgumentSemantics =
    Just "one of the signatures was found to be invalid"

type instance ErrorArg "majorityQuorumNotReached" = ()
instance (CustomErrorHasDoc "majorityQuorumNotReached") where
  customErrClass = ErrClassActionException
  customErrDocMdCause =
    "The number of signatures provided was less than the minimal one"
  customErrArgumentSemantics =
    Just "the number of signatures is too small"

ensureSignatureValid
  :: PublicKey & TSignature ByteString & ByteString & s1 :-> s1
ensureSignatureValid = do
  dup
  dip checkSignature
  swap
  if Holds
  then drop
  else failCustom #invalidSignature
