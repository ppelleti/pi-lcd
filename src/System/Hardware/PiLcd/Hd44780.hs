{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : System.Hardware.PiLcd.Hd44780
Description : Control the HD44780U LCD controller
Copyright   : © Patrick Pelletier, 2017
License     : BSD3
Maintainer  : code@funwithsoftware.org

This module lets you control an HD44780U Dot Matrix Liquid Crystal
Display Controller/Driver
(<https://www.adafruit.com/datasheets/HD44780.pdf datasheet>),
such as the one used in the
<https://www.adafruit.com/category/808 Adafruit LCD+Keypad Kit>.

Only supports 4-bit mode, write only.  The user specifies a
callback for performing the actual I/O to the chip.

Access to the LCD is not threadsafe (you'll need to do your own
locking), but it is safe in the presence of async exceptions.
-}

module System.Hardware.PiLcd.Hd44780
  ( LcdBus (..)
  , LcdCallbacks (..)
  , lcdInitialize
  , lcdClear
  , lcdControl
  , lcdWrite
  , lcdDefineChar
  ) where

import Control.Applicative
import Control.Concurrent
import Control.Exception
import Control.Monad
import Data.Bits
import qualified Data.ByteString as B
import Data.Word
import System.Clock

import System.Hardware.PiLcd.Util

-- Nanoseconds since some arbitrary point in time.
getNanos :: IO Integer
getNanos = toNanoSecs <$> getTime Monotonic

-- Busy-wait for the specified number of nanoseconds.
spin :: Int -> IO ()
spin nanos = do
  start <- getNanos
  let end = start + fromIntegral nanos
      sp = do
        now <- getNanos
        when (now < end) sp
  sp

-- | Argument to 'lcSend'.  Specifies the state of the bus going to
-- the HD44780.  The RW line is always 0, because we only do writes.
data LcdBus =
  LcdBus
  { lbRS :: !Bool  -- ^ Register Select
  , lbE  :: !Bool  -- ^ Enable
  , lbDB :: !Word8 -- ^ 4 LSB are DB4 to DB7
  } deriving (Eq, Ord, Show, Read)

instReg = False
dataReg = True

-- | Callback for communicating with the HD44780.
newtype LcdCallbacks =
  LcdCallbacks
  { lcSend :: LcdBus -> IO () -- ^ Sets the values on the bus.  If using a
                              -- direct parallel interface on a fast processor,
                              -- you may need to insert a brief (500 ns) delay
                              -- after writing to the bus.  (This is
                              -- unnecessary on the LCD+Keypad Kit, because
                              -- the I²C operation of the MCP23017 provides
                              -- more than enough delay.)
  }

write4 :: LcdCallbacks -> Bool -> Word8 -> IO ()
write4 cb rs db = do
  let bus = LcdBus
            { lbRS = rs
            , lbE = False
            , lbDB = db
            }
  lcSend cb $ bus { lbE = True }
  lcSend cb $ bus { lbE = False }

write8 :: LcdCallbacks -> Bool -> Word8 -> IO ()
write8 cb rs db = do
  mask_ $ do
    write4 cb rs (db `shiftR` 4)
    write4 cb rs (db .&. 0xf)
  spin 37000

-- | Initializes the LCD and clears the screen.  You must
-- call this function first, before any of the other
-- LCD functions.
lcdInitialize :: LcdCallbacks -> IO ()
lcdInitialize cb = do
  -- initialization according to Figure 24 (page 45)
  write4 cb instReg 3
  threadDelay 4100
  write4 cb instReg 3
  threadDelay 100
  write4 cb instReg 3
  spin 37000
  write4 cb instReg 2
  spin 37000
  doCmd cb 0x28 -- 2 display lines
  lcdControl cb False False False -- display off
  lcdClear cb
  lcdMode cb True False -- left-to-right, no scrolling
  lcdControl cb True False False -- display on

doCmd :: LcdCallbacks -> Word8 -> IO ()
doCmd cb cmd = do
  write8 cb instReg cmd

doData :: LcdCallbacks -> Word8 -> IO ()
doData cb cmd = do
  write8 cb dataReg cmd

-- | Clears the screen.
lcdClear :: LcdCallbacks -> IO ()
lcdClear cb = do
  doCmd cb (bit 0)
  threadDelay 1520

-- | Controls what is shown on the LCD.
lcdControl :: LcdCallbacks
           -> Bool -- ^ Enable display
           -> Bool -- ^ Enable underline cursor
           -> Bool -- ^ Enable blinking block cursor
           -> IO ()
lcdControl cb d c b =
  doCmd cb (bit 3 +
            bitIf d 2 +
            bitIf c 1 +
            bitIf b 0)

lcdMode :: LcdCallbacks -> Bool -> Bool -> IO ()
lcdMode cb id s =
  doCmd cb (bit 2 +
            bitIf id 1 +
            bitIf s 0)

-- | Writes text onto the screen.  To position the cursor
-- without writing anything, you can write a zero-length string.
lcdWrite :: LcdCallbacks
         -> Word8 -- ^ Line number.  Must be 0 or 1.  (Even
                  -- <https://www.adafruit.com/products/198 displays with four physical lines>
                  -- are modeled internally as 2 lines.)
         -> Word8 -- ^ Column number, starting at 0.
         -> B.ByteString -- ^ Characters to write to the display.  Must be
                         -- encoded in the controller's native character
                         -- encoding.  See Table 4 on pages 17-18 of the
                         -- HD44780U datasheet.
         -> IO ()
lcdWrite cb line col bs = do
  let pos = col + line * 0x40
  doCmd cb (0x80 .|. pos)
  forM_ (B.unpack bs) $ \b -> doData cb b

-- | Defines a custom character.
lcdDefineChar :: LcdCallbacks
              -> Word8   -- ^ The character code to define.  Must be 0-7.
              -> [Word8] -- ^ The bitmap data.  Must be 8 bytes, with
                         -- data in the least significant 5 bits of each byte.
              -> IO ()
lcdDefineChar cb c bitmap = do
  when (c >= 8) $
    fail $ "lcdDefineChar: character must be between 0-7; got " ++ show c
  let len = length bitmap
  when (len /= 8) $
    fail $ "lcdDefineChar: bitmap must have 8 elements; got " ++ show len
  let pos = c * 8
  doCmd cb (0x40 .|. pos)
  forM_ bitmap $ \b -> doData cb b
