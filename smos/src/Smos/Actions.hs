{-# LANGUAGE OverloadedStrings #-}

module Smos.Actions
    ( stop
    -- * Ready-made actions
    , insertTreeAbove
    , insertTreeChild
    , deleteCurrentHeader
    , moveUp
    , moveDown
    , moveLeft
    , moveRight
    -- * Header actions
    , enterHeader
    , headerInsert
    , headerRemove
    , headerDelete
    , headerLeft
    , headerRight
    , exitHeader
    -- * Helper functions to define your own actions
    , modifyEntryM
    , modifyEntry
    , modifyHeaderM
    , modifyHeader
    , modifyCursor
    , modifyMCursor
    , withEntryCursor
    , withHeaderCursor
    , modify
    ) where

import Import

import Control.Monad.State

import Smos.Data

import Smos.Cursor
import Smos.Types

{-# ANN module ("HLint: ignore Use fromMaybe" :: String) #-}

stop :: SmosM a
stop = MkSmosM $ NextT $ pure Stop

emptyTree :: SmosTree
emptyTree = SmosTree {treeEntry = newEntry "", treeForest = SmosForest []}

initEntryCursor :: Maybe ACursor
initEntryCursor =
    let fc = makeForestCursor $ SmosForest []
        fc' = forestCursorInsertAtStart emptyTree fc
        mtc' = forestCursorSelectFirst fc'
    in (AnEntry . treeCursorEntry) <$> mtc'

insertTreeAbove :: SmosM ()
insertTreeAbove =
    modifyMCursor $ \mcur ->
        case mcur of
            Nothing -> initEntryCursor
            Just (AnEntry ec) ->
                let tc = entryCursorParent ec
                    tc' = treeCursorInsertAbove tc emptyTree
                    ec' = treeCursorEntry tc'
                in Just $ AnEntry ec'
            _ -> mcur

insertTreeChild :: SmosM ()
insertTreeChild =
    modifyMCursor $ \mcur ->
        case mcur of
            Nothing -> initEntryCursor
            Just (AnEntry ec) ->
                let tc = entryCursorParent ec
                    tc' = treeCursorInsertChildAtStart emptyTree tc
                    ec' = treeCursorEntry tc'
                    fc' = treeCursorForest tc'
                    mtc' = forestCursorSelectFirst fc'
                    mec' = treeCursorEntry <$> mtc'
                in Just $ maybe (AnEntry ec') AnEntry mec'
            _ -> mcur

deleteCurrentHeader :: SmosM ()
deleteCurrentHeader =
    modifyMCursor $ \mcur ->
        case mcur of
            Just (AnEntry ec) ->
                let tc = entryCursorParent ec
                    eft = treeCursorDeleteCurrent tc
                    mec' =
                        case eft of
                            Left fc ->
                                case forestCursorParent fc of
                                    Nothing -> Nothing
                                    Just tc_ -> Just $ treeCursorEntry tc_
                            Right tc_ -> Just $ treeCursorEntry tc_
                in AnEntry <$> mec'
            _ -> mcur

moveUp :: SmosM ()
moveUp =
    modifyEntry $ \ec ->
        let tc = entryCursorParent ec
            tc' =
                fromMaybe
                    (fromMaybe tc $ forestCursorParent $ treeCursorParent tc)
                    (treeCursorSelectPrev tc)
            ec' = treeCursorEntry tc'
        in ec'

moveDown :: SmosM ()
moveDown =
    modifyEntry $ \ec ->
        let tc = entryCursorParent ec
            goNextViaDown t =
                case forestCursorElems $ treeCursorForest t of
                    [] -> Nothing
                    (tc_:_) -> Just tc_
            goNextViaUp t =
                case treeCursorSelectNext t of
                    Just tc_ -> tc_
                    Nothing ->
                        let fc = treeCursorParent t
                        in case forestCursorParent fc of
                               Nothing -> tc -- CHECKME
                               Just tc_ -> goNextViaUp tc_
            tc' =
                case goNextViaDown tc of
                    Nothing -> goNextViaUp tc
                    Just tc_ -> tc_
            ec' = treeCursorEntry tc'
        in ec'

moveLeft :: SmosM ()
moveLeft =
    modifyEntry $ \ec ->
        let tc = entryCursorParent ec
            tc' = fromMaybe tc $ forestCursorParent $ treeCursorParent tc
            ec' = treeCursorEntry tc'
        in ec'

moveRight :: SmosM ()
moveRight =
    modifyEntry $ \ec ->
        let tc = entryCursorParent ec
            fc = treeCursorForest tc
            tc' = fromMaybe tc $ forestCursorSelectFirst fc
            ec' = treeCursorEntry tc'
        in ec'

enterHeader :: SmosM ()
enterHeader =
    modifyCursor $ \cur ->
        case cur of
            AnEntry ec -> AHeader $ entryCursorHeader ec
            _ -> cur

headerInsert :: Char -> SmosM ()
headerInsert c = modifyHeader $ \hc -> headerCursorInsert c hc

headerRemove :: SmosM ()
headerRemove = modifyHeaderM headerCursorRemove

headerDelete :: SmosM ()
headerDelete = modifyHeaderM headerCursorDelete

headerLeft :: SmosM ()
headerLeft = modifyHeaderM headerCursorLeft

headerRight :: SmosM ()
headerRight = modifyHeaderM headerCursorRight

exitHeader :: SmosM ()
exitHeader =
    modifyCursor $ \cur ->
        case cur of
            AHeader hc -> AnEntry $ headerCursorParent hc
            _ -> cur

modifyEntryM :: (EntryCursor -> Maybe EntryCursor) -> SmosM ()
modifyEntryM func = modifyEntry $ \hc -> fromMaybe hc $ func hc

modifyEntry :: (EntryCursor -> EntryCursor) -> SmosM ()
modifyEntry func =
    modifyCursor $ \cur ->
        case cur of
            AnEntry h -> AnEntry $ func h
            _ -> cur

modifyHeaderM :: (HeaderCursor -> Maybe HeaderCursor) -> SmosM ()
modifyHeaderM func = modifyHeader $ \hc -> fromMaybe hc $ func hc

modifyHeader :: (HeaderCursor -> HeaderCursor) -> SmosM ()
modifyHeader func =
    modifyCursor $ \cur ->
        case cur of
            AHeader h -> AHeader $ func h
            _ -> cur

modifyCursor :: (ACursor -> ACursor) -> SmosM ()
modifyCursor func = modifyMCursor $ \mc -> func <$> mc

modifyMCursor :: (Maybe ACursor -> Maybe ACursor) -> SmosM ()
modifyMCursor func =
    modify $ \ss -> ss {smosStateCursor = func $ smosStateCursor ss}

withEntryCursor :: (EntryCursor -> SmosM ()) -> SmosM ()
withEntryCursor func = do
    ss <- get
    case smosStateCursor ss of
        Just (AnEntry fc) -> func fc
        _ -> pure ()

withHeaderCursor :: (HeaderCursor -> SmosM ()) -> SmosM ()
withHeaderCursor func = do
    ss <- get
    case smosStateCursor ss of
        Just (AHeader fc) -> func fc
        _ -> pure ()
