#!/usr/bin/env Rscript
### =========================================================================
### WOSO LIVE: GOALKEEPER CLUB LOGO & BRAND COLOR SYNC PIPELINE
### Fetches missing club crests from SofaScore / FotMob caches, validates and
### normalizes images to sRGB PNG, extracts modal brand hex colors, audits for
### placeholder hashes, and atomically updates quarto_site/data/club_badges.json.
### =========================================================================

suppressPackageStartupMessages({
  library(qs2)
  library(dplyr)
  library(jsonlite)
  library(magick)
  library(png)
  library(reticulate)
  library(httr)
})

# Configurable league registry: add future leagues here and pass via --leagues=...
LEAGUE_REGISTRY <- list(
  ncaa = list(cache = "ncaa_arbitrage_rapm_data_cache.qs2", provider = "sofascore", label = "NCAA Division I (USA)"),
  usl  = list(cache = "usl_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "USL Super League (USA)"),
  nwsl = list(cache = "arbitrage_rapm_data_cache.qs2",      provider = "fotmob",    label = "NWSL (USA)"),
  wsl  = list(cache = "wsl_arbitrage_rapm_data_cache.qs2",  provider = "fotmob",    label = "WSL (ENG)"),
  wsl2 = list(cache = "wsl2_arbitrage_rapm_data_cache.qs2", provider = "sofascore", label = "WSL2 (ENG)"),
  esp  = list(cache = "esp_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Liga F (ESP)"),
  fra  = list(cache = "fra_arbitrage_rapm_data_cache.qs2",  provider = "fotmob",    label = "Premiere Ligue (FRA)"),
  ger  = list(cache = "ger_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Frauen-Bundesliga (GER)"),
  ita  = list(cache = "ita_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Serie A (ITA)"),
  swe  = list(cache = "swe_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Damallsvenskan (SWE)"),
  eli  = list(cache = "eli_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Elitettan (SWE)"),
  den  = list(cache = "den_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Kvindeliga (DEN)"),
  por  = list(cache = "por_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Campeonato Nacional (POR)"),
  isl  = list(cache = "isl_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Besta deild kvenna (ISL)"),
  nor  = list(cache = "nor_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Toppserien (NOR)"),
  fin  = list(cache = "fin_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Kansallinen Liiga (FIN)"),
  sco  = list(cache = "sco_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "SWPL 1 (SCO)"),
  bra  = list(cache = "bra_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Brasileirao Serie A1 (BRA)"),
  mex  = list(cache = "mex_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Liga MX Femenil (MEX)"),
  jpn  = list(cache = "jpn_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "WE-League (JPN)"),
  aus  = list(cache = "aus_arbitrage_rapm_data_cache.qs2",  provider = "fotmob",    label = "A-League (AUS)"),
  uwcl = list(cache = "uwcl_arbitrage_rapm_data_cache.qs2", provider = "sofascore", label = "UEFA Women's Champions League"),
  afc_ac   = list(cache = "afc_ac_arbitrage_rapm_data_cache.qs2",   provider = "sofascore", label = "AFC Women's Asian Cup"),
  asg      = list(cache = "asg_arbitrage_rapm_data_cache.qs2",      provider = "sofascore", label = "Algarve / Pinatar / Friendly Tournaments"),
  copa_am  = list(cache = "copa_am_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Copa America Femenina"),
  eaff     = list(cache = "eaff_arbitrage_rapm_data_cache.qs2",     provider = "sofascore", label = "EAFF E-1 Football Championship"),
  fifa_ser = list(cache = "fifa_ser_arbitrage_rapm_data_cache.qs2", provider = "sofascore", label = "FIFA Series Women's"),
  intl_fr  = list(cache = "intl_fr_arbitrage_rapm_data_cache.qs2",  provider = "sofascore", label = "Senior International Friendlies"),
  sbc      = list(cache = "sbc_arbitrage_rapm_data_cache.qs2",      provider = "sofascore", label = "SheBelieves Cup"),
  u17      = list(cache = "u17_arbitrage_rapm_data_cache.qs2",      provider = "sofascore", label = "FIFA U-17 Women's World Cup"),
  u20      = list(cache = "u20_arbitrage_rapm_data_cache.qs2",      provider = "sofascore", label = "FIFA U-20 Women's World Cup"),
  unl      = list(cache = "unl_arbitrage_rapm_data_cache.qs2",      provider = "sofascore", label = "UEFA Women's Nations League"),
  weuro    = list(cache = "weuro_arbitrage_rapm_data_cache.qs2",    provider = "sofascore", label = "UEFA Women's EURO"),
  can          = list(cache = "can_arbitrage_rapm_data_cache.qs2",          provider = "sofascore", label = "Northern Super League (CAN)"),
  chn          = list(cache = "chn_arbitrage_rapm_data_cache.qs2",          provider = "sofascore", label = "CFA Women's Super League (CHN)"),
  cze          = list(cache = "cze_arbitrage_rapm_data_cache.qs2",          provider = "sofascore", label = "1. Liga (CZE)"),
  col          = list(cache = "col_arbitrage_rapm_data_cache.qs2",          provider = "sofascore", label = "Liga Femenina (COL)"),
  irl          = list(cache = "irl_arbitrage_rapm_data_cache.qs2",          provider = "sofascore", label = "Women's Premier Division (IRL)"),
  ned          = list(cache = "ned_arbitrage_rapm_data_cache.qs2",          provider = "sofascore", label = "Vrouwen Eredivisie (NED)"),
  pol          = list(cache = "pol_arbitrage_rapm_data_cache.qs2",          provider = "sofascore", label = "Ekstraliga (POL)"),
  rus          = list(cache = "rus_arbitrage_rapm_data_cache.qs2",          provider = "sofascore", label = "Russian Women's Super League (RUS)"),
  lib          = list(cache = "lib_arbitrage_rapm_data_cache.qs2",          provider = "sofascore", label = "Copa Libertadores Femenina"),
  cwcc         = list(cache = "cwcc_arbitrage_rapm_data_cache.qs2",         provider = "sofascore", label = "CONCACAF W Champions Cup"),
  u17_euro     = list(cache = "u17_euro_arbitrage_rapm_data_cache.qs2",     provider = "sofascore", label = "UEFA U-17 Women's EURO"),
  u20_concacaf = list(cache = "u20_concacaf_arbitrage_rapm_data_cache.qs2", provider = "sofascore", label = "CONCACAF U-20 Women's Championship"),
  ofc_nc       = list(cache = "ofc_nc_arbitrage_rapm_data_cache.qs2",       provider = "sofascore", label = "OFC Women's Nations Cup"),
  eng_lc       = list(cache = "eng_lc_arbitrage_rapm_data_cache.qs2",       provider = "sofascore", label = "FA Women's League Cup (ENG)"),
  jpn_lc       = list(cache = "jpn_lc_arbitrage_rapm_data_cache.qs2",       provider = "sofascore", label = "WE League Cup (JPN)"),
  bra_sc       = list(cache = "bra_sc_arbitrage_rapm_data_cache.qs2",       provider = "sofascore", label = "Supercopa Feminina do Brasil (BRA)"),
  esp_sc       = list(cache = "esp_sc_arbitrage_rapm_data_cache.qs2",       provider = "sofascore", label = "Supercopa Femenina (ESP)"),
  usa_cc       = list(cache = "usa_cc_arbitrage_rapm_data_cache.qs2",       provider = "sofascore", label = "NWSL Challenge Cup (USA)"),
  irl_pc       = list(cache = "irl_pc_arbitrage_rapm_data_cache.qs2",       provider = "sofascore", label = "Women's President's Cup (IRL)")
)

parse_cli_args <- function(args) {
  opts <- list(
    leagues  = "ncaa",
    rapm_dir = "C:/Users/iflem/Documents/Work/RAPM_App",
    site_dir = "C:/Users/iflem/OneDrive/Documents/woso_live/quarto_site"
  )
  for (a in args) {
    if (grepl("^--leagues=", a)) {
      opts$leagues <- sub("^--leagues=", "", a)
    } else if (grepl("^--rapm-dir=", a)) {
      opts$rapm_dir <- sub("^--rapm-dir=", "", a)
    } else if (grepl("^--site-dir=", a)) {
      opts$site_dir <- sub("^--site-dir=", "", a)
    }
  }
  opts
}

#' Extract the modal vibrant brand hex color from an sRGB magick image (or PNG fallback).
extract_dominant_brand_color <- function(im_srgb, fallback_png_path = NULL) {
  r <- g <- b <- a <- NULL

  rgba_raw <- tryCatch(magick::image_data(im_srgb, channels = "rgba"), error = function(e) NULL)
  if (!is.null(rgba_raw)) {
    dims <- dim(rgba_raw)
    if (length(dims) == 3 && dims[1] >= 4) {
      arr <- as.integer(as.raw(rgba_raw)) / 255.0
      dim(arr) <- dims
      r <- as.numeric(arr[1, , ])
      g <- as.numeric(arr[2, , ])
      b <- as.numeric(arr[3, , ])
      a <- as.numeric(arr[4, , ])
    }
  }

  if (is.null(r) && !is.null(fallback_png_path) && file.exists(fallback_png_path)) {
    p <- tryCatch(png::readPNG(fallback_png_path), error = function(e) NULL)
    if (!is.null(p) && length(dim(p)) == 3 && dim(p)[3] >= 3) {
      r <- as.vector(p[, , 1])
      g <- as.vector(p[, , 2])
      b <- as.vector(p[, , 3])
      a <- if (dim(p)[3] >= 4) as.vector(p[, , 4]) else rep(1, length(r))
    }
  }

  if (is.null(r)) return("#1D3549")

  keep <- a > 0.5
  r <- r[keep]; g <- g[keep]; b <- b[keep]
  if (length(r) == 0) return("#1D3549")

  mx <- pmax(r, g, b)
  mn <- pmin(r, g, b)
  sat <- ifelse(mx > 0, (mx - mn) / mx, 0)
  lum <- 0.299 * r + 0.587 * g + 0.114 * b

  # Prefer colorful brand pixels; fall back to non-extreme tones for monochrome crests
  brand <- sat > 0.25 & lum > 0.08 & lum < 0.88
  if (sum(brand) < 25) brand <- lum > 0.06 & lum < 0.85
  if (sum(brand) < 10) return("#1D3549")

  rb <- r[brand]; gb <- g[brand]; bb <- b[brand]
  qkey <- paste(round(rb * 15), round(gb * 15), round(bb * 15), sep = "_")
  top_bin <- names(sort(table(qkey), decreasing = TRUE))[1]
  idx <- which(qkey == top_bin)

  grDevices::rgb(mean(rb[idx]), mean(gb[idx]), mean(bb[idx]))
}

#' Validate and convert raw image bytes to a stripped single-frame sRGB PNG.
decode_and_normalize_png <- function(raw_bytes) {
  if (length(raw_bytes) <= 200) return(NULL)
  im <- tryCatch(magick::image_read(raw_bytes), error = function(e) NULL)
  if (is.null(im) || length(im) == 0) return(NULL)

  info <- tryCatch(magick::image_info(im[1]), error = function(e) NULL)
  if (is.null(info) || nrow(info) == 0 || info$width[1] < 16 || info$height[1] < 16) {
    return(NULL)
  }

  tryCatch({
    im_clean <- magick::image_strip(im[1])
    magick::image_convert(im_clean, format = "png", colorspace = "sRGB")
  }, error = function(e) NULL)
}

#' Fetch image bytes with retries and exponential backoff on 429/5xx/network errors.
fetch_image_bytes <- function(url, provider, sofa_session = NULL) {
  max_attempts <- 3L
  for (attempt in seq_len(max_attempts)) {
    Sys.sleep(stats::runif(1, 0.08, 0.15))

    res <- tryCatch({
      if (provider == "sofascore") {
        r <- sofa_session$get(url, timeout = 12)
        list(status = as.integer(r$status_code), bytes = as.raw(r$content), err = NULL)
      } else {
        r <- httr::GET(url, httr::user_agent("Mozilla/5.0"), httr::timeout(12))
        list(status = as.integer(httr::status_code(r)), bytes = httr::content(r, "raw"), err = NULL)
      }
    }, error = function(e) {
      list(status = NA_integer_, bytes = raw(0), err = conditionMessage(e))
    })

    st <- res$status
    if (!is.na(st) && st == 200L) {
      return(list(ok = TRUE, status = 200L, bytes = res$bytes, blocked = FALSE, err = NULL))
    }
    if (!is.na(st) && st == 404L) {
      return(list(ok = FALSE, status = 404L, bytes = raw(0), blocked = FALSE, err = "HTTP 404"))
    }
    if (!is.na(st) && st == 403L) {
      if (attempt < max_attempts) Sys.sleep(2^attempt)
      if (attempt == max_attempts) {
        return(list(ok = FALSE, status = 403L, bytes = raw(0), blocked = TRUE, err = "HTTP 403"))
      }
      next
    }

    is_retryable <- is.na(st) || st == 429L || st >= 500L
    if (is_retryable && attempt < max_attempts) {
      Sys.sleep(2^attempt)
      next
    }
    return(list(
      ok = FALSE,
      status = st,
      bytes = raw(0),
      blocked = (!is.na(st) && (st == 403L || st == 429L)),
      err = res$err %||% paste("HTTP", st)
    ))
  }
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a[1])) b else a

write_png_atomic <- function(im_srgb, dest_path) {
  tmp_path <- paste0(dest_path, ".tmp")
  on.exit(if (file.exists(tmp_path)) unlink(tmp_path), add = TRUE)
  magick::image_write(im_srgb, path = tmp_path, format = "png")
  if (!file.exists(tmp_path) || file.info(tmp_path)$size <= 200) {
    stop(sprintf("Failed writing valid PNG temp file for %s", dest_path))
  }
  ok <- file.rename(tmp_path, dest_path)
  if (!ok) {
    stop(sprintf("Atomic rename failed for %s", dest_path))
  }
}

sync_leagues <- function(opts) {
  league_keys <- trimws(strsplit(opts$leagues, ",")[[1]])
  league_keys <- league_keys[nzchar(league_keys)]
  unknown_keys <- setdiff(league_keys, names(LEAGUE_REGISTRY))
  if (length(unknown_keys) > 0) {
    stop(sprintf("Unknown league key(s): %s. Valid keys: %s",
                 paste(unknown_keys, collapse = ", "),
                 paste(names(LEAGUE_REGISTRY), collapse = ", ")))
  }

  logos_dir     <- file.path(opts$site_dir, "logos")
  data_dir      <- file.path(opts$site_dir, "data")
  manifest_path <- file.path(data_dir, "club_badges.json")
  dir.create(logos_dir, showWarnings = FALSE, recursive = TRUE)
  dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)

  existing_manifest <- if (file.exists(manifest_path)) {
    tryCatch(jsonlite::fromJSON(manifest_path, simplifyVector = FALSE), error = function(e) list())
  } else {
    list()
  }
  if (!is.list(existing_manifest)) existing_manifest <- list()

  needs_sofa <- any(vapply(league_keys, function(k) LEAGUE_REGISTRY[[k]]$provider == "sofascore", logical(1)))
  sofa_session <- NULL
  if (needs_sofa) {
    reticulate::py_require("curl_cffi", action = "add")
    curl_req <- reticulate::import("curl_cffi.requests")
    sofa_session <- curl_req$Session(impersonate = "safari184")
  }

  total_teams     <- 0L
  already_cached  <- 0L
  newly_downloaded <- 0L
  bytes_added     <- 0
  failed_rows     <- list()
  synced_files    <- tibble::tibble(team_id = character(), team_name = character(), file_path = character())

  for (lk in league_keys) {
    cfg <- LEAGUE_REGISTRY[[lk]]
    cache_path <- file.path(opts$rapm_dir, cfg$cache)
    if (!file.exists(cache_path)) {
      stop(sprintf("Cache file not found for league '%s': %s", lk, cache_path))
    }

    message(sprintf("\n=== Syncing %s (%s) via %s ===", cfg$label, lk, cfg$provider))
    cache_obj <- qs2::qs_read(cache_path)
    if (is.null(cache_obj$players) || nrow(cache_obj$players) == 0) {
      message(sprintf("[%s] No players table rows found; skipping.", lk))
      next
    }

    teams_df <- cache_obj$players %>%
      dplyr::transmute(
        team_id   = trimws(as.character(team_id)),
        team_name = trimws(as.character(team_name))
      ) %>%
      dplyr::filter(
        !is.na(team_id) & nzchar(team_id) & team_id != "NA",
        !is.na(team_name) & nzchar(team_name) & team_name != "Unknown" & team_name != "NA"
      ) %>%
      dplyr::group_by(team_name) %>%
      dplyr::summarise(team_id = dplyr::last(team_id), .groups = "drop") %>%
      dplyr::arrange(team_name)

    n_lg <- nrow(teams_df)
    total_teams <- total_teams + n_lg
    message(sprintf("[%s] Found %d unique teams in cache.", lk, n_lg))

    consec_blocks <- 0L

    for (i in seq_len(n_lg)) {
      tid <- teams_df$team_id[i]
      tnm <- teams_df$team_name[i]

      prefix   <- if (cfg$provider == "sofascore") "sofa_" else "fm_"
      filename <- paste0(prefix, tid, ".png")
      rel_path <- paste0("logos/", filename)
      dest     <- file.path(logos_dir, filename)

      im_ready <- NULL
      used_cache <- FALSE

      if (file.exists(dest) && file.info(dest)$size > 200) {
        im_disk <- tryCatch(magick::image_read(dest), error = function(e) NULL)
        if (!is.null(im_disk) && length(im_disk) > 0) {
          info <- tryCatch(magick::image_info(im_disk[1]), error = function(e) NULL)
          if (!is.null(info) && nrow(info) > 0 && info$width[1] >= 16 && info$height[1] >= 16) {
            im_ready <- tryCatch(
              magick::image_convert(magick::image_strip(im_disk[1]), format = "png", colorspace = "sRGB"),
              error = function(e) NULL
            )
            if (!is.null(im_ready) && toupper(info$format[1]) != "PNG") {
              write_png_atomic(im_ready, dest)
            }
            if (!is.null(im_ready)) {
              used_cache <- TRUE
              already_cached <- already_cached + 1L
            }
          }
        }
      }

      if (!used_cache) {
        url <- if (cfg$provider == "sofascore") {
          sprintf("https://www.sofascore.com/api/v1/team/%s/image", tid)
        } else {
          sprintf("https://images.fotmob.com/image_resources/logo/teamlogo/%s.png", tid)
        }

        res <- fetch_image_bytes(url, cfg$provider, sofa_session)
        if (!res$ok) {
          if (isTRUE(res$blocked)) {
            consec_blocks <- consec_blocks + 1L
          } else {
            consec_blocks <- 0L
          }
          failed_rows[[length(failed_rows) + 1L]] <- list(
            league = lk, team_id = tid, team_name = tnm, reason = res$err
          )
          message(sprintf("  [MISS %d/%d] %s (id=%s): %s", i, n_lg, tnm, tid, res$err))
          if (consec_blocks > 5L) {
            stop(sprintf("Aborting '%s': >5 consecutive HTTP 403/429 blocks from %s.", lk, cfg$provider))
          }
          next
        }

        consec_blocks <- 0L
        im_ready <- decode_and_normalize_png(res$bytes)
        if (is.null(im_ready)) {
          failed_rows[[length(failed_rows) + 1L]] <- list(
            league = lk, team_id = tid, team_name = tnm, reason = "Invalid/corrupt image payload"
          )
          message(sprintf("  [INVALID %d/%d] %s (id=%s): could not decode valid image", i, n_lg, tnm, tid))
          next
        }

        write_png_atomic(im_ready, dest)
        newly_downloaded <- newly_downloaded + 1L
        bytes_added <- bytes_added + file.info(dest)$size
      }

      brand_hex <- extract_dominant_brand_color(im_ready, fallback_png_path = dest)
      existing_manifest[[tnm]] <- list(logo = rel_path, color = brand_hex)
      synced_files <- dplyr::bind_rows(
        synced_files,
        tibble::tibble(team_id = tid, team_name = tnm, file_path = dest)
      )

      if (i %% 50L == 0L || i == n_lg) {
        message(sprintf("  Progress [%s]: %d / %d teams processed (downloaded=%d, cached=%d, failed=%d)",
                        lk, i, n_lg, newly_downloaded, already_cached, length(failed_rows)))
      }
    }
  }

  # Post-fetch MD5 duplicate / placeholder crest audit
  md5_warnings <- character()
  if (nrow(synced_files) > 0) {
    uniq_files <- synced_files %>% dplyr::distinct(team_id, file_path)
    hashes <- tools::md5sum(uniq_files$file_path)
    uniq_files$md5 <- unname(hashes)
    dup_hashes <- uniq_files %>%
      dplyr::group_by(md5) %>%
      dplyr::summarise(n_teams = dplyr::n_distinct(team_id),
                       sample_names = paste(utils::head(team_id, 5), collapse = ", "),
                       .groups = "drop") %>%
      dplyr::filter(n_teams >= 3L)

    if (nrow(dup_hashes) > 0) {
      for (r_idx in seq_len(nrow(dup_hashes))) {
        msg <- sprintf("MD5 %s shared by %d team IDs (sample IDs: %s)",
                       dup_hashes$md5[r_idx], dup_hashes$n_teams[r_idx], dup_hashes$sample_names[r_idx])
        md5_warnings <- c(md5_warnings, msg)
      }
    }
  }

  # Verify every manifest entry resolves to an existing non-empty PNG under logos/
  verified_manifest <- list()
  dropped_entries <- character()
  for (tnm in sort(names(existing_manifest))) {
    ent <- existing_manifest[[tnm]]
    rel <- as.character(ent$logo %||% "")
    fp  <- file.path(opts$site_dir, rel)
    if (nzchar(rel) && grepl("^logos/.*\\.png$", rel) && file.exists(fp) && file.info(fp)$size > 200) {
      verified_manifest[[tnm]] <- list(logo = rel, color = as.character(ent$color %||% "#1D3549"))
    } else {
      dropped_entries <- c(dropped_entries, sprintf("%s (%s)", tnm, rel))
    }
  }

  # Atomic write of club_badges.json
  tmp_manifest <- paste0(manifest_path, ".tmp")
  on.exit(if (file.exists(tmp_manifest)) unlink(tmp_manifest), add = TRUE)
  jsonlite::write_json(verified_manifest, tmp_manifest, auto_unbox = TRUE, pretty = TRUE)
  # Validate serialized JSON parses cleanly before promoting
  parsed_check <- jsonlite::fromJSON(tmp_manifest, simplifyVector = FALSE)
  if (!is.list(parsed_check) || length(parsed_check) != length(verified_manifest)) {
    stop("JSON verification failed for club_badges.json.tmp")
  }
  if (!file.rename(tmp_manifest, manifest_path)) {
    stop("Failed atomic rename for club_badges.json")
  }

  message("\n=== LOGO SYNC SUMMARY ===")
  message(sprintf("Total teams in requested caches : %d", total_teams))
  message(sprintf("Already cached (verified PNG)   : %d", already_cached))
  message(sprintf("Newly downloaded & converted    : %d", newly_downloaded))
  message(sprintf("Failed / 404                    : %d", length(failed_rows)))
  message(sprintf("Total bytes added to logos/     : %.1f KB", bytes_added / 1024))
  message(sprintf("Manifest entries written        : %d -> %s", length(verified_manifest), manifest_path))

  if (length(failed_rows) > 0) {
    message("\nFailed / Missing teams:")
    for (fr in failed_rows) {
      message(sprintf("  - [%s] %s (id=%s): %s", fr$league, fr$team_name, fr$team_id, fr$reason))
    }
  }
  if (length(md5_warnings) > 0) {
    message("\n[WARNING] Potential generic/placeholder MD5 hashes (>=3 teams share identical PNG):")
    for (w in md5_warnings) message("  - ", w)
  } else {
    message("MD5 placeholder check           : PASS (no MD5 shared by >=3 team IDs)")
  }
  if (length(dropped_entries) > 0) {
    message("\n[WARNING] Dropped invalid manifest entries:")
    for (d in dropped_entries) message("  - ", d)
  }
}

opts <- parse_cli_args(commandArgs(trailingOnly = TRUE))
sync_leagues(opts)
