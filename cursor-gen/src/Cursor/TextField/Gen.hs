{-# OPTIONS_GHC -fno-warn-orphans #-}

module Cursor.TextField.Gen where

import Import

import Cursor.Text.Gen ()
import Cursor.TextField

instance GenUnchecked TextFieldCursor

instance GenValid TextFieldCursor
