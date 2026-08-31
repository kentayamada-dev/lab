env "local" {
  src = getenv("ATLAS_SRC")
  url = getenv("DB_URL")
  dev = getenv("ATLAS_DB_URL")

  migration {
    dir = getenv("ATLAS_DIR")
  }
}
