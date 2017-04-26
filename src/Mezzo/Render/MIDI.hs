{-# LANGUAGE ScopedTypeVariables #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Mezzo.Render.MIDI
-- Description :  MIDI exporting
-- Copyright   :  (c) Dima Szamozvancev
-- License     :  MIT
--
-- Maintainer  :  ds709@cam.ac.uk
-- Stability   :  experimental
-- Portability :  portable
--
-- Functions for exporting Mezzo compositions into MIDI files.
-- Skeleton code by Stephen Lavelle.
--
-----------------------------------------------------------------------------

module Mezzo.Render.MIDI
    ( section, renderScore, renderSections )
    where

import Mezzo.Model
import Mezzo.Compose (_th, _si, _ei, _qu, _ha, _wh)
import Mezzo.Render.Score

import Codec.Midi hiding (key)
import qualified Codec.Midi as CM (key)

-------------------------------------------------------------------------------
-- Types
-------------------------------------------------------------------------------

-- | A MIDI representation of a musical note.
data MidiNote = MidiNote
    { noteNum :: Int        -- ^ MIDI number of a note (middle C is 60).
    , vel     :: Velocity   -- ^ Performance velocity of the note.
    , start   :: Ticks      -- ^ Relative start time of the note.
    , noteDur :: Ticks      -- ^ Duration of the note.
    } deriving Show

-- | A MIDI event: a MIDI message at a specific timestamp.
type MidiEvent = (Ticks, Message)

-- | A sequence of MIDI events.
type MidiTrack = Track Ticks

-------------------------------------------------------------------------------
-- Operations
-------------------------------------------------------------------------------

-- | Play a MIDI note with the specified duration and default velocity.
midiNote :: Int -> Ticks -> MidiNote
midiNote root dur = MidiNote {noteNum = root, vel = 100, start = 0, noteDur = dur}

midiRest :: Ticks -> MidiNote
midiRest dur = MidiNote {noteNum = 60, vel = 0, start = 0, noteDur = dur}

-- | Start playing the specified 'MidiNote'.
keyDown :: MidiNote -> MidiEvent
keyDown n = (start n, NoteOn {channel = 0, CM.key = noteNum n, velocity = vel n})

-- | Stop playing the specified 'MidiNote'.
keyUp :: MidiNote -> MidiEvent
keyUp n = (start n + noteDur n, NoteOn {channel = 0, CM.key = noteNum n, velocity = 0})

-- | Play the specified 'MidiNote'.
playNote :: Int -> Ticks -> MidiTrack
playNote root dur = map ($ midiNote root (dur * 60)) [keyDown, keyUp]

-- | Play a rest of the specified duration.
playRest :: Ticks -> MidiTrack
playRest dur = map ($ midiRest (dur * 60)) [keyDown, keyUp]

-- | Play the specified 'MidiNote'.
playTriplet :: [Int] -> Ticks -> MidiTrack
playTriplet ts dur = concatMap playShortNote ts
    where playShortNote root = map ($ midiNote root (dur * 40)) [keyDown, keyUp]

-- | Merge two parallel MIDI tracks.
(><) :: MidiTrack -> MidiTrack -> MidiTrack
m1 >< m2 = removeTrackEnds $ m1 `merge` m2

-------------------------------------------------------------------------------
-- Rendering
-------------------------------------------------------------------------------

-- | Title of a composition
type Title = String

-- | Convert a 'Music' piece into a 'MidiTrack'.
musicToMidi :: forall t k m r. Music (Sig :: Signature t k r) m -> MidiTrack
musicToMidi (m1 :|: m2) = musicToMidi m1 ++ musicToMidi m2
musicToMidi (m1 :-: m2) = musicToMidi m1 >< musicToMidi m2
musicToMidi (Note root dur) = playNote (prim root) (prim dur)
musicToMidi (Rest dur) = playRest (prim dur)
musicToMidi (Chord c d) = foldr1 (><) notes
    where notes = map (`playNote` prim d) $ prim c
musicToMidi (Progression p) = foldr1 (++) chords
    where chords = (toChords <$> init (prim p)) ++ [cadence (last (prim p))]
          toChords :: [Int] -> MidiTrack
          toChords = concat . replicate (prim (TimeSig @t)) . foldr1 (><) . map (`playNote` prim _qu)
          cadence :: [Int] -> MidiTrack
          cadence = foldr1 (><) . map (`playNote` prim _wh)
musicToMidi (Homophony m a) = musicToMidi m >< musicToMidi a
musicToMidi (Triplet d r1 r2 r3) = playTriplet [prim r1, prim r2, prim r3] (prim d)

-- | Pre-render one section of a long composition. The first argument is only
-- for documentation purposes.
section :: String -> Score -> MidiTrack
section _ (Score atts m) =
    [ (0, getTimeSig atts)
    , (0, getKeySig atts)
    , (0, TempoChange (60000000 `div` tempo atts))
    ] ++ musicToMidi m

-- | A basic skeleton of a MIDI file.
midiSkeleton :: Title -> MidiTrack -> Midi
midiSkeleton trName mel = Midi
    { fileType = SingleTrack
    , timeDiv = TicksPerBeat 480
    , tracks =
        [ [ (0, ChannelPrefix 0)
          , (0, TrackName trName)
          , (0, InstrumentName "GM Device  1")
          ]
        ++ mel
        ++ [ (0, TrackEnd) ]
        ]
    }

-- | Create a MIDI file with the specified name and track.
exportMidi :: FilePath -> Title -> MidiTrack -> IO ()
exportMidi f trName notes = do
    exportFile f $ midiSkeleton trName notes
    putStrLn $ "Composition rendered to " ++ f ++ "."


-- | Create a MIDI file with the specified path and score.
renderScore :: FilePath -> Score -> IO ()
renderScore f s@(Score atts m) = do
    exportMidi f (title atts) (section "" s)
    putStrLn $ "Composition rendered to " ++ f ++ "."


-- | Render a list of baked scores into a MIDI file with the given title.
renderSections :: FilePath -> Title -> [MidiTrack] -> IO ()
renderSections f compTitle ts = do
    exportMidi f compTitle (concat ts)
    putStrLn $ "Composition rendered to " ++ f ++ "."
    
