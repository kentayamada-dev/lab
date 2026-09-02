#!/bin/bash
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<EOSQL
CREATE DATABASE "$DB_NAME";

-- Throwaway database Atlas uses to compute schema diffs.
CREATE DATABASE "$ATLAS_DEV_DB";
EOSQL
