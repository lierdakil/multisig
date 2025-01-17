{-# OPTIONS_GHC -Wno-orphans #-}
{-# LANGUAGE RebindableSyntax #-}
module Lorentz.Contracts.Multisig
  ( Order
  , Parameter (..)
  , Signatures
  , Storage (..)
  , ValueToSign (..)
  , CallArgs (..)
  , mkRotateKeysOrder
  , mkCallOrder
  , multisigContract
  ) where

import Lorentz

import Lorentz.Contracts.Multisig.Common
import Lorentz.Contracts.Multisig.Error ()
import Lorentz.Contracts.Multisig.Parameter
import Lorentz.Contracts.Multisig.Storage

multisigContract :: ContractCode Parameter Storage
multisigContract = do
  amount; push (toMutez 0)
  if IsEq
  then nop
  else failCustom_ #nonzeroAmountReceived
  unpair
  dup; dip updateNonceIfCorrect
  dupTop2; checkSignatures
  toField #order
  caseT $
    ( #cCall /-> do
        unit; exec
        dip nil; cons; pair

    , #cRotateKeys /-> do
        setField #teamKeys
        nil; pair
    )
