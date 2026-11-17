#!/usr/bin/env Rscript
# ==============================================================================
# WoSo.Live — 2027 Women's World Cup Simulator Static Web Asset Exporter
# ==============================================================================
# Extracts exact Poisson GLM and Ordered Logit (polr) parameters, team rankings,
# UEFA rankings, alias mappings, precomputed Monte Carlo odds, and declarative
# tournament rules from wwc_app_data.qs2 into quarto_site/data/wwc/wwc_payload.json.
#
# Usage (from quarto_site directory):
#   Rscript scripts/export_wwc_web_assets.R
#   Rscript scripts/export_wwc_web_assets.R --qs2=C:/path/to/wwc_app_data.qs2
#   Rscript scripts/export_wwc_web_assets.R --out-dir=data/wwc --config=data/wwc/wwc_config.json
#   Rscript scripts/export_wwc_web_assets.R --refresh-models --source=C:/path/to/womens_international_rankings.R
# ==============================================================================

suppressPackageStartupMessages({
  library(qs2)
  library(dplyr)
  library(MASS)
  library(jsonlite)
})

# --- 1. CLI & PATH RESOLUTION ---
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg) > 0) normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/", mustWork = FALSE) else ""
script_dir <- if (nzchar(script_path)) dirname(script_path) else getwd()

trailing <- commandArgs(trailingOnly = TRUE)
get_arg <- function(prefix) {
  hit <- grep(paste0("^", prefix, "="), trailing, value = TRUE)
  if (length(hit) > 0) sub(paste0("^", prefix, "="), "", hit[1]) else ""
}
has_flag <- function(flag) {
  any(trailing == flag)
}

resolve_quarto_dir <- function() {
  wd <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(wd, "_quarto.yml"))) return(wd)
  if (file.exists(file.path(wd, "quarto_site", "_quarto.yml"))) return(file.path(wd, "quarto_site"))
  if (nzchar(script_dir)) {
    cand <- normalizePath(dirname(script_dir), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(cand, "_quarto.yml"))) return(cand)
  }
  return(wd)
}

quarto_dir <- resolve_quarto_dir()

out_dir_arg <- get_arg("--out-dir")
out_dir <- if (nzchar(out_dir_arg)) out_dir_arg else file.path(quarto_dir, "data", "wwc")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

config_arg <- get_arg("--config")
config_path <- if (nzchar(config_arg)) config_arg else file.path(out_dir, "wwc_config.json")

qs2_arg <- get_arg("--qs2")
env_qs2 <- Sys.getenv("WOSO_WWC_QS2", "")
qs2_candidates <- unique(c(
  if (nzchar(qs2_arg)) qs2_arg else NULL,
  if (nzchar(env_qs2)) env_qs2 else NULL,
  file.path(quarto_dir, "data", "wwc_app_data.qs2"),
  file.path(quarto_dir, "wwc_app_data.qs2"),
  file.path(dirname(quarto_dir), "wwc_app_data.qs2"),
  "C:/Users/iflem/Documents/Work/WWC_App/wwc_app_data.qs2",
  "C:/Users/iflem/Documents/Work/wwc_app/wwc_app_data.qs2",
  "C:/Users/iflem/Documents/Work/WWC/wwc_app_data.qs2",
  "C:/Users/iflem/Documents/Work/WWC_Simulator/wwc_app_data.qs2",
  "C:/Users/iflem/OneDrive/Documents/Work/WWC_App/wwc_app_data.qs2",
  "C:/Users/iflem/OneDrive/Documents/wwc_app_data.qs2",
  "/home/antigravity/wwc_app_data.qs2"
))

qs2_path <- ""
for (cand in qs2_candidates) {
  if (nzchar(cand) && file.exists(cand)) {
    qs2_path <- normalizePath(cand, winslash = "/", mustWork = TRUE)
    break
  }
}

refresh_models <- has_flag("--refresh-models")
source_arg <- get_arg("--source")

if (refresh_models) {
  src_candidates <- unique(c(
    if (nzchar(source_arg)) source_arg else NULL,
    if (nzchar(qs2_path)) file.path(dirname(qs2_path), "womens_international_rankings.R") else NULL,
    "C:/Users/iflem/Documents/Work/WWC_App/womens_international_rankings.R",
    "C:/Users/iflem/Documents/Work/wwc_app/womens_international_rankings.R",
    "/home/antigravity/womens_international_rankings.R"
  ))
  src_file <- ""
  for (sc in src_candidates) {
    if (nzchar(sc) && file.exists(sc)) {
      src_file <- normalizePath(sc, winslash = "/", mustWork = TRUE)
      break
    }
  }
  if (!nzchar(src_file)) {
    stop("--refresh-models requested, but womens_international_rankings.R was not found. Pass --source=<path>.")
  }
  cat(sprintf("[WWC Exporter] Refreshing models from %s...\n", src_file))
  model_env <- new.env(parent = globalenv())
  sys.source(src_file, envir = model_env)
  wwc_payload <- list(
    df_master_probs    = model_env$run_global_monte_carlo(iterations = 10000),
    df_champs          = model_env$run_tournament_monte_carlo(iterations = 10000),
    lookups            = list(),
    df_rankings_wwr    = model_env$df_rankings_wwr,
    df_rankings_adv    = model_env$df_rankings_adv,
    wwr_full_env       = model_env$wwr_full_env,
    wwr_logit_model    = model_env$wwr_logit_model,
    fit_poisson_full   = model_env$fit_poisson_full,
    shared_levels_full = model_env$shared_levels_full,
    uefa_rankings      = model_env$uefa_rankings
  )
  target_qs2 <- if (nzchar(qs2_path)) qs2_path else file.path(quarto_dir, "data", "wwc_app_data.qs2")
  qs2::qs_save(wwc_payload, target_qs2)
  qs2_path <- target_qs2
  cat(sprintf("[WWC Exporter] Updated %s\n", qs2_path))
} else {
  if (!nzchar(qs2_path)) {
    stop(paste0(
      "Unable to locate wwc_app_data.qs2.\n",
      "Pass --qs2=C:/path/to/wwc_app_data.qs2 or set WOSO_WWC_QS2 env var.\n",
      "Searched:\n  - ", paste(qs2_candidates, collapse = "\n  - ")
    ))
  }
  cat(sprintf("[WWC Exporter] Reading payload: %s\n", qs2_path))
  wwc_payload <- qs2::qs_read(qs2_path)
}

cat(sprintf("[WWC Exporter] Output directory: %s\n", out_dir))

# --- 2. LOAD OR INITIALIZE DECLARATIVE CONFIG ---
default_config <- function() {
  list(
    schema_version = 1L,
    tournament_title = "2027 Women's World Cup Simulator",
    as_of_label = "Post-WAFCON 2026 Cycle",
    host_team = "Brazil",
    fallback_lambda = 1.25,
    fallback_wwr = 1300,
    aliases = list(
      "China PR" = "China",
      "South Korea" = "Korea Republic",
      "North Korea" = "Korea DPR",
      "Taiwan" = "Chinese Taipei",
      "Czechia" = "Czech Republic",
      "Cabo Verde" = "Cape Verde",
      "Côte d'Ivoire" = "Ivory Coast",
      "Ireland" = "Republic of Ireland"
    ),
    confed_teams = list(
      AFC = list("Japan", "Australia", "China PR", "China", "South Korea", "Korea Republic", "North Korea", "Korea DPR", "Philippines", "Taiwan", "Chinese Taipei", "Uzbekistan"),
      CAF = list("Morocco", "Algeria", "Senegal", "Kenya", "South Africa", "Ivory Coast", "Burkina Faso", "Tanzania", "Nigeria", "Zambia", "Egypt", "Malawi", "Ghana", "Cameroon", "Mali", "Cape Verde"),
      CONCACAF = list("United States", "El Salvador", "Jamaica", "Costa Rica", "Canada", "Panama", "Mexico", "Haiti"),
      CONMEBOL = list("Brazil", "Colombia", "Argentina", "Ecuador", "Venezuela"),
      OFC = list("New Zealand", "Papua New Guinea"),
      UEFA_EXTRA = list("Denmark", "France", "Germany", "Spain")
    ),
    direct_qualifiers = list(
      host = list("Brazil"),
      afc = list("Japan", "Australia", "China PR", "South Korea", "North Korea", "Philippines"),
      ofc = list("New Zealand"),
      conmebol = list("Colombia", "Argentina"),
      uefa_direct = list("Denmark", "France", "Germany", "Spain")
    ),
    caf = list(
      label = "CAF 2026 WAFCON",
      window = "July-August 2026",
      status = "completed",
      host = "Morocco",
      note = "Settled at 2026 WAFCON (Morocco): Algeria, Morocco, Cameroon, and Malawi qualified directly; Ghana and South Africa advanced to the Inter-Confederation Play-offs.",
      direct = list("Algeria", "Morocco", "Cameroon", "Malawi"),
      playoff = list("Ghana", "South Africa"),
      groups = list(
        A = list("Morocco", "Algeria", "Senegal", "Kenya"),
        B = list("South Africa", "Ivory Coast", "Burkina Faso", "Tanzania"),
        C = list("Nigeria", "Zambia", "Egypt", "Malawi"),
        D = list("Ghana", "Cameroon", "Mali", "Cape Verde")
      )
    ),
    uefa = list(
      label = "UEFA Play-offs",
      window = "October-December 2026",
      status = "upcoming",
      two_legged = TRUE,
      direct = NULL,
      playoff = NULL,
      r1_path1 = list(
        list("Lithuania", "Sweden"),
        list("Romania", "Norway"),
        list("Greece", "England"),
        list("Croatia", "Iceland"),
        list("Kazakhstan", "Republic of Ireland"),
        list("Kosovo", "Austria"),
        list("Hungary", "Netherlands"),
        list("Belarus", "Italy")
      ),
      r1_path2 = list(
        list("Albania", "Wales"),
        list("Turkey", "Slovenia"),
        list("Slovakia", "Ukraine"),
        list("Israel", "Switzerland"),
        list("Belgium", "Poland"),
        list("Czech Republic", "Scotland"),
        list("Northern Ireland", "Portugal"),
        list("Finland", "Serbia")
      ),
      r2_pairings = list(list(2L, 2L), list(7L, 7L), list(6L, 3L), list(0L, 1L), list(3L, 5L), list(5L, 0L), list(4L, 4L), list(1L, 6L))
    ),
    concacaf = list(
      label = "CONCACAF W Championship",
      window = "November-December 2026",
      status = "upcoming",
      host = "United States",
      direct = NULL,
      playoff = NULL,
      final_winner = NULL,
      qf = list(
        list("United States", "El Salvador"),
        list("Canada", "Panama"),
        list("Mexico", "Haiti"),
        list("Jamaica", "Costa Rica")
      ),
      sf_pairings = list(list(0L, 3L), list(1L, 2L)),
      pi_pairings = list(list(0L, 3L), list(1L, 2L))
    ),
    inter_confed = list(
      label = "Inter-Confederation Play-offs",
      window = "Nov-Dec 2026 & Feb 2027",
      status = "upcoming",
      afc = list("Taiwan", "Uzbekistan"),
      conmebol = list("Ecuador", "Venezuela"),
      ofc = "Papua New Guinea",
      prelim_schedule = list(
        list(0L, 2L), list(0L, 3L), list(0L, 4L),
        list(1L, 2L), list(1L, 3L), list(1L, 5L),
        list(2L, 5L), list(3L, 4L), list(4L, 5L)
      ),
      prelim_advancers = NULL,
      qualifiers = NULL
    ),
    draw_rules = list(
      groups = list("A", "B", "C", "D", "E", "F", "G", "H"),
      host_group = "A",
      uefa_max_per_group = 2L,
      non_uefa_max_per_group = 1L,
      max_retries = 200L
    ),
    wwc_final = list(
      status = "upcoming",
      pots = NULL,
      groups = NULL,
      knockout_order = list(
        list("A1", "B2"), list("C1", "D2"), list("E1", "F2"), list("G1", "H2"),
        list("B1", "A2"), list("D1", "C2"), list("F1", "E2"), list("H1", "G2")
      )
    )
  )
}

if (file.exists(config_path)) {
  config <- jsonlite::fromJSON(config_path, simplifyVector = FALSE)
  cat(sprintf("[WWC Exporter] Loaded config: %s\n", config_path))
} else {
  config <- default_config()
  jsonlite::write_json(config, config_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  cat(sprintf("[WWC Exporter] Wrote default config: %s\n", config_path))
}

# --- 3. EXTRACT & VERIFY EXACT POISSON GLM AND ORDERED LOGIT (POLR) PARAMETERS ---
fit_poisson <- wwc_payload$fit_poisson_full
shared_levels <- as.character(wwc_payload$shared_levels_full)
wwr_logit <- wwc_payload$wwr_logit_model
wwr_env <- wwc_payload$wwr_full_env

if (is.null(fit_poisson) || length(shared_levels) == 0 || is.null(wwr_logit)) {
  stop("wwc_app_data.qs2 is missing fit_poisson_full, shared_levels_full, or wwr_logit_model.")
}

p_coefs <- stats::coef(fit_poisson)
ref_team <- shared_levels[1]
poisson_intercept <- unname(as.numeric(p_coefs[["(Intercept)"]]))
poisson_home_adv <- unname(as.numeric(p_coefs[["home_adv"]]))
if (is.na(poisson_intercept) || is.na(poisson_home_adv)) {
  stop("Failed extracting (Intercept) or home_adv from fit_poisson_full.")
}

poisson_teams <- list()
for (t in shared_levels) {
  a_val <- if (t == ref_team) 0 else unname(as.numeric(p_coefs[paste0("team", t)]))
  d_val <- if (t == ref_team) 0 else unname(as.numeric(p_coefs[paste0("opponent", t)]))
  if (is.na(a_val)) a_val <- 0
  if (is.na(d_val)) d_val <- 0
  poisson_teams[[t]] <- list(a = round(a_val, 8), d = round(d_val, 8))
}

# Strict Poisson parity verification (< 1e-7 rounding error due to 8dp serialization, exact unrounded < 1e-12)
probe_pool <- intersect(
  c(ref_team, "United States", "Brazil", "England", "Spain", "Germany", "Japan", "France", "Sweden", "Norway", "Morocco", "Canada"),
  shared_levels
)
if (length(probe_pool) < 4) probe_pool <- head(shared_levels, 6)

max_lam_exact_err <- 0
max_lam_ser_err <- 0
for (t1 in probe_pool) {
  for (t2 in probe_pool) {
    if (t1 == t2) next
    for (h in c(0, 1)) {
      pred_r <- as.numeric(suppressWarnings(stats::predict(
        fit_poisson,
        newdata = data.frame(
          team = factor(t1, levels = shared_levels),
          opponent = factor(t2, levels = shared_levels),
          home_adv = h
        ),
        type = "response"
      )))
      a_raw <- if (t1 == ref_team) 0 else unname(as.numeric(p_coefs[paste0("team", t1)]))
      d_raw <- if (t2 == ref_team) 0 else unname(as.numeric(p_coefs[paste0("opponent", t2)]))
      if (is.na(a_raw)) a_raw <- 0
      if (is.na(d_raw)) d_raw <- 0
      lam_exact <- exp(poisson_intercept + a_raw + d_raw + h * poisson_home_adv)
      lam_ser <- exp(poisson_intercept + poisson_teams[[t1]]$a + poisson_teams[[t2]]$d + h * poisson_home_adv)
      max_lam_exact_err <- max(max_lam_exact_err, abs(lam_exact - pred_r))
      max_lam_ser_err <- max(max_lam_ser_err, abs(lam_ser - pred_r))
    }
  }
}
stopifnot(max_lam_exact_err < 1e-12, max_lam_ser_err < 1e-6)
cat(sprintf("[WWC Exporter] * Poisson GLM parity verified across %d pairs (exact=%.3e, serialized=%.3e)\n",
            length(probe_pool) * (length(probe_pool) - 1L) * 2L, max_lam_exact_err, max_lam_ser_err))

# Ordered Logit (MASS::polr) parameters
polr_beta <- unname(as.numeric(wwr_logit$coefficients[["rating_diff_adj"]]))
polr_zeta <- wwr_logit$zeta
zeta_away_draw <- unname(as.numeric(polr_zeta[["AwayWin|Draw"]]))
zeta_draw_home <- unname(as.numeric(polr_zeta[["Draw|HomeWin"]]))
stopifnot(!is.na(polr_beta), !is.na(zeta_away_draw), !is.na(zeta_draw_home))

max_polr_err <- 0
test_diffs <- c(-800, -450, -200, -100, -25, 0, 25, 100, 200, 450, 800)
r_polr_mat <- stats::predict(wwr_logit, newdata = data.frame(rating_diff_adj = test_diffs), type = "probs")
for (i in seq_along(test_diffs)) {
  eta <- polr_beta * test_diffs[i]
  p_away <- stats::plogis(zeta_away_draw - eta)
  p_draw <- stats::plogis(zeta_draw_home - eta) - p_away
  p_home <- 1 - stats::plogis(zeta_draw_home - eta)
  e_i <- max(
    abs(p_away - unname(r_polr_mat[i, "AwayWin"])),
    abs(p_draw - unname(r_polr_mat[i, "Draw"])),
    abs(p_home - unname(r_polr_mat[i, "HomeWin"]))
  )
  max_polr_err <- max(max_polr_err, e_i)
}
stopifnot(max_polr_err < 1e-12)
cat(sprintf("[WWC Exporter] * WWR Ordered Logit (polr) parity verified (max_err=%.3e)\n", max_polr_err))

# --- 4. RANKINGS, RATINGS, UEFA SEEDINGS & PRECOMPUTED ODDS ---
df_wwr <- wwc_payload$df_rankings_wwr %>%
  dplyr::transmute(
    rank = as.integer(Rank),
    team = as.character(Team),
    rating = round(as.numeric(WWR_Rating), 3)
  ) %>%
  dplyr::arrange(rank)

df_adv <- wwc_payload$df_rankings_adv %>%
  dplyr::transmute(
    rank = as.integer(Rank),
    team = as.character(Team),
    net_strength = round(as.numeric(Net_Strength), 5),
    attack = round(as.numeric(Attack), 5),
    defense = round(-as.numeric(Defense_Weakness), 5)
  ) %>%
  dplyr::arrange(rank)

# Complete WWR rating dictionary (env + table union)
wwr_ratings <- list()
if (is.environment(wwr_env)) {
  env_list <- as.list(wwr_env)
  for (nm in names(env_list)) {
    v <- suppressWarnings(as.numeric(env_list[[nm]]))
    if (!is.na(v)) wwr_ratings[[nm]] <- round(v, 3)
  }
}
for (i in seq_len(nrow(df_wwr))) {
  if (is.null(wwr_ratings[[df_wwr$team[i]]])) {
    wwr_ratings[[df_wwr$team[i]]] <- df_wwr$rating[i]
  }
}

uefa_vec <- wwc_payload$uefa_rankings
uefa_rank_list <- list()
for (nm in names(uefa_vec)) {
  uefa_rank_list[[nm]] <- as.integer(uefa_vec[[nm]])
}

parse_prob_col <- function(x) {
  if (is.numeric(x)) return(as.numeric(x))
  as.numeric(sub("%$", "", as.character(x))) / 100
}

precomputed_playoff_odds <- list()
precomputed_qual_odds <- list()
if (!is.null(wwc_payload$df_master_probs) && nrow(wwc_payload$df_master_probs) > 0) {
  df_mp <- wwc_payload$df_master_probs %>%
    dplyr::transmute(
      team = as.character(Team),
      prob = round(parse_prob_col(Probability), 5)
    ) %>%
    dplyr::arrange(desc(prob))
  prob_sum <- sum(df_mp$prob, na.rm = TRUE)
  if (prob_sum > 10) {
    precomputed_qual_odds <- lapply(seq_len(nrow(df_mp)), function(i) {
      list(team = df_mp$team[i], prob = df_mp$prob[i])
    })
    cat(sprintf("[WWC Exporter] * Detected 32-team qualification table in df_master_probs (sum=%.2f, n=%d)\n", prob_sum, nrow(df_mp)))
  } else {
    precomputed_playoff_odds <- lapply(seq_len(nrow(df_mp)), function(i) {
      list(team = df_mp$team[i], prob = df_mp$prob[i])
    })
    cat(sprintf("[WWC Exporter] * Detected 3-slot Inter-Confed Play-off table in df_master_probs (sum=%.2f, n=%d)\n", prob_sum, nrow(df_mp)))
  }
}

precomputed_champ_odds <- list()
if (!is.null(wwc_payload$df_champs) && nrow(wwc_payload$df_champs) > 0) {
  df_ch <- wwc_payload$df_champs %>%
    dplyr::transmute(
      team = as.character(Team),
      win_prob = round(parse_prob_col(Win_Prob), 6)
    ) %>%
    dplyr::arrange(desc(win_prob))
  precomputed_champ_odds <- lapply(seq_len(nrow(df_ch)), function(i) {
    list(team = df_ch$team[i], win_prob = df_ch$win_prob[i])
  })
}

# Reconcile aliases cleanly against actual shared_levels_full in this payload
aliases <- if (!is.null(config$aliases)) config$aliases else list()
model_level_set <- shared_levels
# Add reverse hints automatically only if the alias target actually exists in model levels
resolved_aliases <- list()
for (k in names(aliases)) {
  target <- as.character(aliases[[k]])
  if (target %in% model_level_set) {
    resolved_aliases[[k]] <- target
  } else if (k %in% model_level_set) {
    # Handle case where model itself was trained using display spelling (e.g. "Taiwan")
    resolved_aliases[[target]] <- k
  } else {
    resolved_aliases[[k]] <- target
  }
}

# --- 5. BUILD & WRITE UNIFIED WEB PAYLOAD ---
web_payload <- list(
  meta = list(
    generated_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    source_qs2 = basename(qs2_path),
    n_model_teams = length(shared_levels),
    n_wwr_teams = nrow(df_wwr),
    n_adv_teams = nrow(df_adv)
  ),
  models = list(
    poisson = list(
      intercept = round(poisson_intercept, 8),
      home_adv = round(poisson_home_adv, 8),
      fallback_lambda = as.numeric(config$fallback_lambda %||% 1.25),
      teams = poisson_teams
    ),
    wwr_polr = list(
      beta = round(polr_beta, 10),
      zeta_away_draw = round(zeta_away_draw, 10),
      zeta_draw_home = round(zeta_draw_home, 10),
      home_bonus = 100,
      fallback_rating = as.numeric(config$fallback_wwr %||% 1300),
      ratings = wwr_ratings
    )
  ),
  aliases = resolved_aliases,
  rankings = list(
    wwr = lapply(seq_len(nrow(df_wwr)), function(i) {
      list(rank = df_wwr$rank[i], team = df_wwr$team[i], rating = df_wwr$rating[i])
    }),
    net_strength = lapply(seq_len(nrow(df_adv)), function(i) {
      list(
        rank = df_adv$rank[i],
        team = df_adv$team[i],
        net_strength = df_adv$net_strength[i],
        attack = df_adv$attack[i],
        defense = df_adv$defense[i]
      )
    })
  ),
  uefa_rankings = uefa_rank_list,
  precomputed_odds = list(
    playoff_3slots = precomputed_playoff_odds,
    qual_32slots = precomputed_qual_odds,
    champions = precomputed_champ_odds
  ),
  config = config
)

out_json_path <- file.path(out_dir, "wwc_payload.json")
json_txt <- jsonlite::toJSON(web_payload, auto_unbox = TRUE, null = "null", digits = 8)
writeLines(json_txt, out_json_path, useBytes = TRUE)

fsize_kb <- file.info(out_json_path)$size / 1024
cat(sprintf("[WWC Exporter] Wrote %s (%.1f KB, %d Poisson teams, %d WWR teams, %d Champion entries)\n",
            out_json_path, fsize_kb, length(shared_levels), nrow(df_wwr), length(precomputed_champ_odds)))
