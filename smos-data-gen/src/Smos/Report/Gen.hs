{-# OPTIONS_GHC -fno-warn-orphans #-}

module Smos.Report.Gen where

import Import

import Smos.Data.Gen ()
import Smos.Report

instance GenUnchecked EntryReport

instance GenValid EntryReport where
    genValid = EntryReport <$> genValid