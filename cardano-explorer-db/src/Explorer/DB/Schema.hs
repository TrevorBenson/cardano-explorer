{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Explorer.DB.Schema where

import Data.ByteString.Char8 (ByteString)
import Data.Text (Text)
import Data.Time.Clock (UTCTime)
import Data.Word (Word16, Word64)

-- Do not use explicit imports from this module as the imports can change
-- from version to version due to changes to the TH code in Persistent.
import Database.Persist.TH

-- In the schema definition we need to match Haskell types with with the
-- custom type defined in PostgreSQL (via 'DOMAIN' statements). For the
-- time being the Haskell types will be simple Haskell types like
-- 'ByteString' and 'Word64'.

-- We use camelCase here in the Haskell schema definition and 'persistLowerCase'
-- specifies that all the table and column names are converted to lower snake case.

share
  [ mkPersist sqlSettings
  , mkDeleteCascade sqlSettings
  , mkMigrate "migrateExplorerDB"
  ]
  [persistLowerCase|

  -- Schema versioning has three stages to best allow handling of schema migrations.
  --    Stage 1: Set up PostgreSQL data types (using SQL 'DOMAIN' statements).
  --    Stage 2: Persistent generated migrations.
  --    Stage 3: Set up 'VIEW' tables (for use by other languages and applications).
  -- This table should have a single row.
  SchemaVersion
    stageOne Int
    stageTwo Int
    stageThree Int

  SlotLeader
    hash                ByteString          sqltype=hash28type
    description         Text                -- Description of the Slots leader.
    UniqueSlotLeader    hash

  -- Each table has autogenerated primary key named 'id', the Haskell type
  -- of which is (for instance for this table) 'BlockId'. This specific
  -- primary key Haskell type can be used in a type-safe way in the rest
  -- of the schema definition.
  -- All NULL-able fields other than 'epochNo' are NULL for EBBs, whereas 'epochNo' is
  -- only NULL for the genesis block.
  Block
    hash                ByteString          sqltype=hash32type
    epochNo             Word64 Maybe        sqltype=uinteger
    slotNo              Word64 Maybe        sqltype=uinteger
    blockNo             Word64 Maybe        sqltype=uinteger
    previous            BlockId Maybe
    merkelRoot          ByteString Maybe    sqltype=hash32type
    slotLeader          SlotLeaderId
    size                Word64              sqltype=uinteger
    time                UTCTime             sqltype=timestamp
    txCount             Word64              sqltype=uinteger
    UniqueBlock         hash

  Tx
    hash                ByteString          sqltype=hash32type
    block               BlockId             -- This type is the primary key for the 'block' table.
    outSum              Word64              sqltype=lovelace
    fee                 Word64              sqltype=lovelace
    size                Word64              sqltype=uinteger
    UniqueTx            hash

  TxOut
    txId                TxId                -- This type is the primary key for the 'tx' table.
    index               Word16              sqltype=txindex
    address             Text
    value               Word64              sqltype=lovelace
    UniqueTxout         txId index          -- The (tx_id, index) pair must be unique.

  TxIn
    txInId              TxId                -- The transaction where this is used as an input.
    txOutId             TxId                -- The transaction where this was created as an output.
    txOutIndex          Word16              sqltype=txindex
    UniqueTxin          txOutId txOutIndex

  -- A table containing metadat about the chain. There will probably only ever be one
  -- row in this table.
  Meta
    protocolConst       Word64              -- The block security parameter.
    slotDuration        Word64              -- Slot duration in milliseconds.
                                            -- System start time used to calculate slot time stamps.
                                            -- Use 'sqltype' here to force timestamp without time zone.
    startTime           UTCTime             sqltype=timestamp
    networkName         Text Maybe
    UniqueMeta          startTime


  -- The following are tables used my specific 'plugins' to the regular explorer-db-node
  -- functionality. In the regular explorer-db-node these tables will be empty.

  -- The Epoch table is an aggregation of data in the 'Block' table, but is kept in this form
  -- because having it as a 'VIEW' is incredibly slow and inefficient.
  Epoch
    outSum              Word64              sqltype=uinteger
    txCount             Word64              sqltype=uinteger
    no                  Word64              sqltype=uinteger
    startTime           UTCTime             sqltype=timestamp
    endTime             UTCTime             sqltype=timestamp
    UniqueEpoch         no

  |]

