{-
    This file is part of funsat.

    funsat is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    funsat is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public License
    along with funsat.  If not, see <http://www.gnu.org/licenses/>.

    Copyright 2008 Denis Bueno
-}

{-|

Tabular output.

Converting any matrix of showable data types into a tabular form for which the
layout is automatically done properly.  Currently there is no maximum row
width, just a dynamically-calculated column width.

If the input matrix is mal-formed, the largest well-formed submatrix is
chosen.  That is, elements along too-long dimensions are chopped off.

-}
module Text.Tabular( Table(..), mkTable, combine, unTable ) where

import Data.List( intercalate )

newtype Table a = Table [Row a]            -- table is a list of rows
newtype Row a = Row [Cell a]
data Cell a = Cell { cellWidth :: !Int
                   -- the width of a cell is the max of the widths of the
                   -- string representations of all the elements in the column
                   -- in which this cell occurs
                   , cellData :: !a } -- element printed in box of colWidth

mkTable :: (Show a) => [[a]] -> Table a
mkTable rows = Table $ mkRows rows
  where
    widths      = colWidths rows
    mkRows rows = [ Row (map mkCell (zip widths row)) | row <- rows ]
    mkCell      = uncurry Cell

unTable :: Table a -> [[a]]
unTable (Table rows) = [ map cellData r | (Row r) <- rows ]

combine :: (Show a) => Table a -> Table a -> Table a
-- slow impl but works
combine t t' = mkTable (unTable t ++ unTable t')

-- returns a list of the widths of each column
colWidths :: (Show a) => [[a]] -> [Int]
colWidths = map (maximum . map (length . show)) . zipn

-- Pretty, columnar output.
instance (Show a) => Show (Table a) where
    show (Table rows) = intercalate "\n" $ map showRow rows 
        where
          showRow (Row cols) = intercalate " " $ colStrings
            where
              colStrings = [ padString (cellWidth c) (show d)
                             | c@(Cell {cellData=d}) <- cols ]

padString maxWidth str = str ++ replicate padLen ' '
    where padLen = maxWidth - length str

zipn xss | any null xss = []
zipn xss = map head xss : zipn (map tail xss)

                  