{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE RecordWildCards #-}

module Smos.Cursor
    ( ACursor(..)
    , makeACursor
    , makeASelection
    , Rebuild(..)
    , Build(..)
    , ForestCursor
    , makeForestCursor
    , forestCursorParent
    , forestCursorElems
    , forestCursorSelectIx
    , forestCursorSelectFirst
    , forestCursorSelectLast
    , forestCursorInsertAt
    , forestCursorInsertAtStart
    , forestCursorInsertAtEnd
    , TreeCursor
    , treeCursorParent
    , treeCursorPrevElemens
    , treeCursorNextElemens
    , treeCursorIndex
    , treeCursorEntry
    , treeCursorForest
    , treeCursorSelectPrev
    , treeCursorSelectNext
    , treeCursorEntryL
    , treeCursorForestL
    , treeCursorInsertAbove
    , treeCursorInsertBelow
    , treeCursorInsertChildAt
    , treeCursorInsertChildAtStart
    , treeCursorInsertChildAtEnd
    , treeCursorDeleteCurrent
    , EntryCursor
    , entryCursorParent
    , entryCursorHeader
    , entryCursorState
    , entryCursorHeaderL
    , entryCursorStateL
    , HeaderCursor
    , headerCursor
    , headerCursorParent
    , headerCursorHeader
    , headerCursorTextCursorL
    , headerCursorInsert
    , headerCursorRemove
    , headerCursorDelete
    , headerCursorLeft
    , headerCursorRight
    , headerCursorStart
    , headerCursorEnd
    , StateCursor
    , stateCursor
    , stateCursorParent
    , stateCursorState
    , stateCursorClear
    , stateCursorSetState
    ) where

import Import

import Data.HashMap.Lazy (HashMap)
import Data.Time

import Lens.Micro

import Smos.Data
import Smos.TextCursor

class Rebuild a where
    rebuild :: a -> SmosForest

class Build a where
    type Building a :: *
    build :: a -> Building a

data ACursor
    = AnEntry EntryCursor
    | AHeader HeaderCursor
    | AState StateCursor

makeACursor :: SmosFile -> Maybe ACursor
makeACursor SmosFile {..} =
    (AnEntry . treeCursorEntry) <$>
    forestCursorSelectFirst (makeForestCursor smosFileForest)

makeASelection :: ACursor -> [Int]
makeASelection = reverse . go
  where
    go (AnEntry ec) = goe ec
    go (AHeader hc) = goh hc
    go (AState sc) = gos sc
    gof ForestCursor {..} = maybe [] ((1 :) . got) forestCursorParent
    got TreeCursor {..} = treeCursorIndex : gof treeCursorParent
    goe EntryCursor {..} = 0 : got entryCursorParent
    goh HeaderCursor {..} =
        gotxt headerCursorHeader : 0 : goe headerCursorParent
    gos StateCursor {..} = 1 : goe stateCursorParent
    gotxt = length . textCursorPrev

instance Rebuild ACursor where
    rebuild (AnEntry ec) = rebuild ec
    rebuild (AHeader hc) = rebuild hc
    rebuild (AState sc) = rebuild sc

data ForestCursor = ForestCursor
    { forestCursorParent :: Maybe TreeCursor
    , forestCursorElems :: [TreeCursor]
    }

instance Validity ForestCursor where
    isValid = isValid . rebuild
    validate = validate . rebuild

instance Show ForestCursor where
    show ForestCursor {..} =
        unlines
            $(case forestCursorParent of
                  Nothing -> "Nothing"
                  Just _ -> "Just [..]") :
        map ((" -" ++) . show) forestCursorElems

instance Rebuild ForestCursor where
    rebuild fc =
        case forestCursorParent fc of
            Nothing -> build fc
            Just pc -> rebuild pc

instance Build ForestCursor where
    type Building ForestCursor = SmosForest
    build = SmosForest . map build . forestCursorElems

makeForestCursor :: SmosForest -> ForestCursor
makeForestCursor = forestCursor Nothing

forestCursor :: Maybe TreeCursor -> SmosForest -> ForestCursor
forestCursor mpar sf = fc
  where
    fc =
        ForestCursor
        { forestCursorParent = mpar
        , forestCursorElems = treeElems fc $ smosTrees sf
        }

forestElemsL ::
       Functor f
    => ([TreeCursor] -> f [TreeCursor])
    -> ForestCursor
    -> f ForestCursor
forestElemsL = lens getter setter
  where
    getter = forestCursorElems
    setter ForestCursor {..} elems = fc'
      where
        fc' =
            ForestCursor
            { forestCursorParent =
                  rebuildForestParentCursor (const fc') forestCursorParent
            , forestCursorElems = elems
            }

rebuildForestParentCursor ::
       (ForestCursor -> ForestCursor) -> Maybe TreeCursor -> Maybe TreeCursor
rebuildForestParentCursor func mtc =
    (\tc -> tc & treeCursorForestL %~ func) <$> mtc

forestCursorSelectIx :: ForestCursor -> Int -> Maybe TreeCursor
forestCursorSelectIx fc = atMay $ forestCursorElems fc

forestCursorSelectFirst :: ForestCursor -> Maybe TreeCursor
forestCursorSelectFirst fc =
    case forestCursorElems fc of
        [] -> Nothing
        (tc:_) -> Just tc

forestCursorSelectLast :: ForestCursor -> Maybe TreeCursor
forestCursorSelectLast fc =
    case reverse $ forestCursorElems fc of
        [] -> Nothing
        (tc:_) -> Just tc

forestCursorInsertAt :: Int -> SmosTree -> ForestCursor -> ForestCursor
forestCursorInsertAt ix_ newTree fc = fc'
  where
    fc' =
        fc & forestElemsL %~
        (\els ->
             treeElems fc' $
             map build (prevs els) ++ [newTree] ++ map build (nexts els))
    ffilter rel = filter ((`rel` ix_) . treeCursorIndex)
    prevs = ffilter (<)
    nexts = ffilter (>=)

forestCursorInsertAtStart :: SmosTree -> ForestCursor -> ForestCursor
forestCursorInsertAtStart = forestCursorInsertAt 0

forestCursorInsertAtEnd :: SmosTree -> ForestCursor -> ForestCursor
forestCursorInsertAtEnd t fc =
    forestCursorInsertAt (length $ forestCursorElems fc) t fc

data TreeCursor = TreeCursor
    { treeCursorParent :: ForestCursor
    , treeCursorPrevElemens :: [TreeCursor] -- ^ In reverse order, so that the first element is the nearest.
    , treeCursorNextElemens :: [TreeCursor]
    , treeCursorIndex :: Int
    , treeCursorEntry :: EntryCursor
    , treeCursorForest :: ForestCursor
    }

instance Validity TreeCursor where
    isValid = isValid . rebuild
    validate = validate . rebuild

instance Rebuild TreeCursor where
    rebuild = rebuild . treeCursorParent

instance Show TreeCursor where
    show TreeCursor {..} =
        unlines
            ("[..]" :
             map
                 (" |-" ++)
                 (concat
                      [ map (const "tree") treeCursorPrevElemens
                      , [ "---"
                        , unwords
                              [ show treeCursorIndex
                              , show $ build treeCursorEntry
                              , show $ build treeCursorForest
                              ]
                        , "---"
                        ]
                      , map (const "tree") treeCursorNextElemens
                      ]))

instance Build TreeCursor where
    type Building TreeCursor = SmosTree
    build TreeCursor {..} =
        SmosTree
        {treeEntry = build treeCursorEntry, treeForest = build treeCursorForest}

treeCursorEntryL ::
       Functor f => (EntryCursor -> f EntryCursor) -> TreeCursor -> f TreeCursor
treeCursorEntryL = lens getter setter
  where
    getter = treeCursorEntry
    setter tc ec = treeCursorModify (const ec) id tc

treeCursorForestL ::
       Functor f
    => (ForestCursor -> f ForestCursor)
    -> TreeCursor
    -> f TreeCursor
treeCursorForestL = lens getter setter
  where
    getter = treeCursorForest
    setter tc fc = treeCursorModify id (const fc) tc

treeCursorModify ::
       (EntryCursor -> EntryCursor)
    -> (ForestCursor -> ForestCursor)
    -> TreeCursor
    -> TreeCursor
treeCursorModify efunc ffunc tc = tc''
  where
    tc' =
        tc
        { treeCursorEntry = efunc $ treeCursorEntry tc
        , treeCursorForest = ffunc $ treeCursorForest tc
        }
    tcs =
        reverse (treeCursorPrevElemens tc) ++ [tc'] ++ treeCursorNextElemens tc
    trees = map build tcs
    fc = treeCursorParent tc & forestElemsL .~ els
    els = treeElems fc trees
    tc'' = els !! treeCursorIndex tc

treeElems :: ForestCursor -> [SmosTree] -> [TreeCursor]
treeElems fc sts = tcs
  where
    tcs = zipWith tc [0 ..] sts
    tc i st = cur
      where
        cur =
            TreeCursor
            { treeCursorParent = fc
            , treeCursorPrevElemens =
                  reverse $ filter ((< i) . treeCursorIndex) tcs
            , treeCursorNextElemens = filter ((> i) . treeCursorIndex) tcs
            , treeCursorIndex = i
            , treeCursorEntry = entryCursor cur $ treeEntry st
            , treeCursorForest = fc'
            }
        fc' = forestCursor (Just cur) (treeForest st)

treeCursorSelectPrev :: TreeCursor -> Maybe TreeCursor
treeCursorSelectPrev tc =
    case treeCursorPrevElemens tc of
        [] -> Nothing
        (tc':_) -> Just tc'

treeCursorSelectNext :: TreeCursor -> Maybe TreeCursor
treeCursorSelectNext tc =
    case treeCursorNextElemens tc of
        [] -> Nothing
        (tc':_) -> Just tc'

treeCursorInsertAbove :: TreeCursor -> SmosTree -> TreeCursor
treeCursorInsertAbove tc t = fromJust $ forestCursorSelectIx newpar newIx
  where
    newIx = treeCursorIndex tc
    newpar = forestCursorInsertAt newIx t (treeCursorParent tc)

treeCursorInsertBelow :: TreeCursor -> SmosTree -> TreeCursor
treeCursorInsertBelow tc t =
    fromJust $ forestCursorSelectIx newpar $ treeCursorIndex tc + 1
  where
    newIx = treeCursorIndex tc + 1
    newpar = forestCursorInsertAt newIx t (treeCursorParent tc)

treeCursorInsertChildAt :: Int -> SmosTree -> TreeCursor -> TreeCursor
treeCursorInsertChildAt ix_ t tc =
    tc & treeCursorForestL %~ forestCursorInsertAt ix_ t

treeCursorInsertChildAtStart :: SmosTree -> TreeCursor -> TreeCursor
treeCursorInsertChildAtStart = treeCursorInsertChildAt 0

treeCursorInsertChildAtEnd :: SmosTree -> TreeCursor -> TreeCursor
treeCursorInsertChildAtEnd t tc =
    treeCursorInsertChildAt
        (length $ forestCursorElems $ treeCursorForest tc)
        t
        tc

treeCursorDeleteCurrent :: TreeCursor -> Either ForestCursor TreeCursor
treeCursorDeleteCurrent tc = tc''
  where
    tcs = reverse (treeCursorPrevElemens tc) ++ treeCursorNextElemens tc
    trees = map build tcs
    for = treeCursorParent tc & forestElemsL .~ els
    els = treeElems for trees
    tc'' =
        let ix_ = treeCursorIndex tc
        in maybe (Left for) Right $
           (els `atMay` ix_) `mplus` (els `atMay` (ix_ - 1))

data EntryCursor = EntryCursor
    { entryCursorParent :: TreeCursor
    , entryCursorHeader :: HeaderCursor
    , entryCursorContents :: Maybe Contents
    , entryCursorTimestamps :: HashMap TimestampName UTCTime
    , entryCursorState :: StateCursor
    , entryCursorTags :: [Tag]
    , entryCursorLogbook :: Logbook
    }

instance Validity EntryCursor where
    isValid = isValid . rebuild
    validate = validate . rebuild

instance Show EntryCursor where
    show EntryCursor {..} =
        unlines
            ("[Tree]" :
             map
                 (" |- " ++)
                 [ "[Header]: " ++ show (build entryCursorHeader)
                 , show entryCursorContents
                 , show entryCursorTimestamps
                 , "[State]: " ++ show (build entryCursorState)
                 , show entryCursorTags
                 , show entryCursorLogbook
                 ])

instance Rebuild EntryCursor where
    rebuild = rebuild . entryCursorParent

instance Build EntryCursor where
    type Building EntryCursor = Entry
    build EntryCursor {..} =
        Entry
        { entryHeader = build entryCursorHeader
        , entryContents = entryCursorContents
        , entryTimestamps = entryCursorTimestamps
        , entryState = build entryCursorState
        , entryTags = entryCursorTags
        , entryLogbook = entryCursorLogbook
        }

entryCursor :: TreeCursor -> Entry -> EntryCursor
entryCursor par Entry {..} = ec
  where
    ec =
        EntryCursor
        { entryCursorParent = par
        , entryCursorHeader = headerCursor ec entryHeader
        , entryCursorContents = entryContents
        , entryCursorTimestamps = entryTimestamps
        , entryCursorState = stateCursor ec entryState
        , entryCursorTags = entryTags
        , entryCursorLogbook = entryLogbook
        }

entryCursorHeaderL ::
       Functor f
    => (HeaderCursor -> f HeaderCursor)
    -> EntryCursor
    -> f EntryCursor
entryCursorHeaderL = lens getter setter
  where
    getter = entryCursorHeader
    setter ec hc = ec'
      where
        ec' =
            ec
            { entryCursorParent = entryCursorParent ec & treeCursorEntryL .~ ec'
            , entryCursorHeader = hc
            , entryCursorState = (entryCursorState ec) {stateCursorParent = ec'}
            }

entryCursorStateL ::
       Functor f
    => (StateCursor -> f StateCursor)
    -> EntryCursor
    -> f EntryCursor
entryCursorStateL = lens getter setter
  where
    getter = entryCursorState
    setter ec hc = ec'
      where
        ec' =
            ec
            { entryCursorParent = entryCursorParent ec & treeCursorEntryL .~ ec'
            , entryCursorHeader =
                  (entryCursorHeader ec) {headerCursorParent = ec'}
            , entryCursorState = hc
            }

data HeaderCursor = HeaderCursor
    { headerCursorParent :: EntryCursor
    , headerCursorHeader :: TextCursor
    }

instance Validity HeaderCursor where
    isValid = isValid . rebuild
    validate = validate . rebuild

instance Show HeaderCursor where
    show HeaderCursor {..} =
        unlines
            ["[Entry]", " |-" ++ show (rebuildTextCursor headerCursorHeader)]

instance Rebuild HeaderCursor where
    rebuild = rebuild . headerCursorParent

instance Build HeaderCursor where
    type Building HeaderCursor = Header
    build HeaderCursor {..} = Header $ rebuildTextCursor headerCursorHeader

headerCursor :: EntryCursor -> Header -> HeaderCursor
headerCursor par h =
    HeaderCursor
    { headerCursorParent = par
    , headerCursorHeader = makeTextCursor $ headerText h
    }

headerCursorInsert :: Char -> HeaderCursor -> HeaderCursor
headerCursorInsert c = headerCursorTextCursorL %~ textCursorInsert c

headerCursorRemove :: HeaderCursor -> Maybe HeaderCursor
headerCursorRemove = headerCursorTextCursorL textCursorRemove

headerCursorDelete :: HeaderCursor -> Maybe HeaderCursor
headerCursorDelete = headerCursorTextCursorL textCursorDelete

headerCursorLeft :: HeaderCursor -> Maybe HeaderCursor
headerCursorLeft = headerCursorTextCursorL textCursorSelectPrev

headerCursorRight :: HeaderCursor -> Maybe HeaderCursor
headerCursorRight = headerCursorTextCursorL textCursorSelectNext

headerCursorStart :: HeaderCursor -> HeaderCursor
headerCursorStart = headerCursorTextCursorL %~ textCursorSelectStart

headerCursorEnd :: HeaderCursor -> HeaderCursor
headerCursorEnd = headerCursorTextCursorL %~ textCursorSelectEnd

headerCursorTextCursorL ::
       Functor f
    => (TextCursor -> f TextCursor)
    -> HeaderCursor
    -> f HeaderCursor
headerCursorTextCursorL = lens getter setter
  where
    getter = headerCursorHeader
    setter hc tc = hc'
      where
        hc' =
            HeaderCursor
            { headerCursorParent =
                  headerCursorParent hc & entryCursorHeaderL .~ hc'
            , headerCursorHeader = tc
            }

data StateCursor = StateCursor
    { stateCursorParent :: EntryCursor
    , stateCursorState :: Maybe TodoState
    }

instance Validity StateCursor where
    isValid = isValid . rebuild
    validate = validate . rebuild

instance Show StateCursor where
    show StateCursor {..} = unlines ["[Entry]", " |-" ++ show stateCursorState]

instance Rebuild StateCursor where
    rebuild = rebuild . stateCursorParent

instance Build StateCursor where
    type Building StateCursor = Maybe TodoState
    build StateCursor {..} = stateCursorState

stateCursor :: EntryCursor -> Maybe TodoState -> StateCursor
stateCursor = StateCursor

stateCursorStateL ::
       Functor f
    => (Maybe TodoState -> f (Maybe TodoState))
    -> StateCursor
    -> f StateCursor
stateCursorStateL = lens getter setter
  where
    getter = stateCursorState
    setter sc ts = sc'
      where
        sc' =
            StateCursor
            { stateCursorParent =
                  stateCursorParent sc & entryCursorStateL .~ sc'
            , stateCursorState = ts
            }

stateCursorClear :: StateCursor -> StateCursor
stateCursorClear sc = sc & stateCursorStateL .~ Nothing

stateCursorSetState :: TodoState -> StateCursor -> StateCursor
stateCursorSetState ts sc = sc & stateCursorStateL .~ Just ts
