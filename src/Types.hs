{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Types where

import Control.Monad (mzero)
import Data.Csv ((.!))
import Data.Ratio (numerator, denominator)
import Data.Scientific (Scientific)
import Data.Time.Clock (UTCTime)

import qualified Data.Csv as Csv
import qualified Data.Text as T

-- TODO: Save all this in a Persistent database


-- FIELDS

-- | An Amount of a Coin that has been Bought/Sold, or a Per-Unit Price.
-- TODO: Make Integer Instead of Rational, Need to Figure Out Atomic Units
newtype Quantity
    = Quantity
        { fromQuantity :: Rational
        } deriving (Eq, Num, Fractional)

-- | Show 8 Decimal Places by Default.
instance Show Quantity where
    show = showQuantity 8

-- | Read a `Quantity` from a `Scientific`-formatted String
readDecimalQuantity :: String -> Quantity
readDecimalQuantity =
    Quantity . toRational . (read :: String -> Scientific)

-- | Render a `Quantity` with a Fixed Number of Decimal Places
showQuantity :: Int -> Quantity -> String
showQuantity decimalPlaces (Quantity rat) =
    showRational decimalPlaces rat

-- | Render a `Rational` with a Fixed Number of Decimal Places
showRational :: Int -> Rational -> String
showRational decimalPlaces rat =
    sign ++ shows wholePart ("." ++ fractionalString ++ zeroPadding)
    where
        sign =
            if num < 0 then
                "-"
            else
                ""
        fractionalString =
            take decimalPlaces (buildFractionalString fractionalPart)
        zeroPadding =
            replicate (decimalPlaces - length fractionalString) '0'
        (wholePart, fractionalPart) =
            abs num `quotRem` den
        num =
            numerator rat
        den =
            denominator rat
        buildFractionalString 0 =
            ""
        buildFractionalString fraction =
            let
                (digit, remainingFraction) =
                    (10 * fraction) `quotRem` den
            in
                shows digit (buildFractionalString remainingFraction)


-- | Used as an Identifier for CryptoCurrencies.
newtype Currency
    = Currency { toSymbol :: String }
    deriving (Ord, Eq)

-- | Currencies are Represented by their Ticker Symbol
instance Show Currency where
    show = toSymbol

-- | The `Currency` Representing Ethereum.
eth :: Currency
eth =
    Currency "ETH"



-- TRANSACTIONS

data Transaction
    = Transaction
        { transactionData :: TransactionData
        , transactionDate :: UTCTime
        , transactionGroup :: T.Text
        , transactionComment :: T.Text
        } deriving (Show)

-- | TODO: Change all `Exchange` fields to `Account`? To make more general for wallets
data TransactionData
    = Trade TradeData
    | Income IncomeData
    | Expense ExpenseData
    | Transfer TransferData
    deriving (Show)

data TradeData
    = TradeData
        { tradeBuyQuantity :: Quantity
        , tradeBuyCurrency :: Currency
        , tradeSellQuantity :: Quantity
        , tradeSellCurrency :: Currency
        , tradeFeeQuantity :: Maybe Quantity
        , tradeFeeCurrency :: Maybe Currency
        , tradeExchange :: T.Text
        } deriving (Show)

data IncomeData
    = IncomeData
        { incomeQuantity :: Quantity
        , incomeCurrency :: Currency
        , incomeFeeQuantity :: Maybe Quantity
        , incomeFeeCurrency :: Maybe Currency
        , incomeExchange :: T.Text
        } deriving (Show)

data ExpenseData
    = ExpenseData
        { expenseQuantity :: Quantity
        , expenseCurrency :: Currency
        , expenseFeeQuantity :: Maybe Quantity
        , expenseFeeCurrency :: Maybe Currency
        , expenseExchange :: T.Text
        } deriving (Show)

data TransferData
    = TransferData
        { transferQuantity :: Quantity
        , transferCurrency :: Currency
        , transferFeeQuantity :: Maybe Quantity
        , transferFeeCurrency :: Maybe Currency
        , transferSourceExchange :: T.Text
        , transferDestinationExchange :: T.Text
        } deriving (Show)


-- | Parse a Transaction from a CoinTracking.Info `Trade Table` Export
--
-- We have to use index-based parsing here because the export contains
-- 3 `"Cur."` columns
instance Csv.FromRecord Transaction where
    parseRecord v =
        if length v == 11 then do
            transactionType <- v .! 0
            date <- read <$> v .! 10
            group <- v .! 8
            comment <- v .! 9
            data_ <-
                if transactionType == ("Trade" :: String) then
                    Trade <$>
                        ( TradeData
                            <$> (readDecimalQuantity <$> v .! 1)
                            <*> (Currency <$> v .! 2)
                            <*> (readDecimalQuantity <$> v .! 3)
                            <*> (Currency <$> v .! 4)
                            <*> (fmap readDecimalQuantity <$> v .! 5)
                            <*> (fmap Currency <$> v .! 6)
                            <*> v .! 7
                        )
                else if isIncome transactionType then
                    Income <$>
                        ( IncomeData
                            <$> (readDecimalQuantity <$> v .! 1)
                            <*> (Currency <$> v .! 2)
                            <*> (fmap readDecimalQuantity <$> v .! 5)
                            <*> (fmap Currency <$> v .! 6)
                            <*> v .! 7
                        )
                else if isExpense transactionType then
                    Expense <$>
                        ( ExpenseData
                            <$> (readDecimalQuantity <$> v .! 3)
                            <*> (Currency <$> v .! 4)
                            <*> (fmap readDecimalQuantity <$> v .! 5)
                            <*> (fmap Currency <$> v .! 6)
                            <*> v .! 7
                        )
                else
                    mzero
            return $ Transaction data_ date group comment
        else
            mzero
        where
            isIncome =
                (`elem` ["Income", "Mining", "Gift/Tip", "Deposit"])
            isExpense =
                (`elem` ["Withdrawal", "Spend", "Donation", "Gift", "Stolen/Hacked/Fraud", "Lost"])