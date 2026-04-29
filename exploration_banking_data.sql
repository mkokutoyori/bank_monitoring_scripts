--==============================================================================
-- Script d'exploration : cartographie des donnees Clients / Comptes / KYC
-- Cible : Oracle 12c (FLEXCUBE / core banking)
-- Mode  : SELECT only - aucune modification de donnees
-- Auteur: Data Exploration
--==============================================================================
SET LINESIZE 300
SET PAGESIZE 200
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LONG 32000
COLUMN TABLE_NAME       FORMAT A35
COLUMN COLUMN_NAME      FORMAT A35
COLUMN DATA_TYPE        FORMAT A15
COLUMN CONSTRAINT_NAME  FORMAT A30
COLUMN OWNER            FORMAT A15
COLUMN COMMENTS         FORMAT A60
COLUMN VAL              FORMAT A40
COLUMN DESCRIPTION      FORMAT A60

PROMPT
PROMPT ##############################################################################
PROMPT # SECTION 1 - INVENTAIRE DES TABLES PERTINENTES
PROMPT ##############################################################################

-- 1.1 Tables candidates par mot-cle (CUST/CUSTOMER/CIF/ACCOUNT/ACCT/KYC/DOC)
PROMPT
PROMPT --- 1.1 Tables candidates (USER_TABLES) ---
SELECT  t.table_name,
        t.num_rows                                AS num_rows_stats,
        t.last_analyzed,
        tc.comments                               AS table_comment
FROM    user_tables       t
LEFT JOIN user_tab_comments tc ON tc.table_name = t.table_name
WHERE   REGEXP_LIKE(t.table_name,'CUST|CIF|ACCOUNT|ACCT|KYC|DOC','i')
ORDER BY t.num_rows DESC NULLS LAST;

-- 1.2 Vues candidates (souvent les ecrans front s'appuient dessus)
PROMPT
PROMPT --- 1.2 Vues candidates (USER_VIEWS) ---
SELECT  v.view_name,
        vc.comments AS view_comment
FROM    user_views          v
LEFT JOIN user_tab_comments vc ON vc.table_name = v.view_name
WHERE   REGEXP_LIKE(v.view_name,'CUST|CIF|ACCOUNT|ACCT|KYC|DOC','i')
ORDER BY v.view_name;

-- 1.3 Synonymes pointant vers ces tables/vues
PROMPT
PROMPT --- 1.3 Synonymes ---
SELECT  synonym_name, table_owner, table_name
FROM    user_synonyms
WHERE   REGEXP_LIKE(table_name,'CUST|CIF|ACCOUNT|ACCT|KYC|DOC','i')
ORDER BY synonym_name;

-- 1.4 Comptage reel (utile car USER_TABLES.NUM_ROWS depend des stats)
PROMPT
PROMPT --- 1.4 Comptage reel des tables cibles ---
SELECT 'STTM_CUSTOMER'              AS tbl, COUNT(*) AS nb FROM STTM_CUSTOMER             UNION ALL
SELECT 'STTM_CUST_PERSONAL'         , COUNT(*)         FROM STTM_CUST_PERSONAL        UNION ALL
SELECT 'STTM_CUST_ACCOUNT'          , COUNT(*)         FROM STTM_CUST_ACCOUNT         UNION ALL
SELECT 'STTB_ACCOUNT'               , COUNT(*)         FROM STTB_ACCOUNT              UNION ALL
SELECT 'STTM_KYC_MASTER'            , COUNT(*)         FROM STTM_KYC_MASTER           UNION ALL
SELECT 'STTM_KYC_RETAIL'            , COUNT(*)         FROM STTM_KYC_RETAIL           UNION ALL
SELECT 'STTM_KYC_CORPORATE'         , COUNT(*)         FROM STTM_KYC_CORPORATE        UNION ALL
SELECT 'STTM_KYC_CORP_KEYPERSONS'   , COUNT(*)         FROM STTM_KYC_CORP_KEYPERSONS  UNION ALL
SELECT 'STTM_ACCOUNT_CLASS'         , COUNT(*)         FROM STTM_ACCOUNT_CLASS        UNION ALL
SELECT 'STTM_CUSTOMER_CAT'          , COUNT(*)         FROM STTM_CUSTOMER_CAT         UNION ALL
SELECT 'CLTB_ACCOUNT_APPS_MASTER'   , COUNT(*)         FROM CLTB_ACCOUNT_APPS_MASTER  UNION ALL
SELECT 'CLTB_ACCOUNT_COMPONENTS'    , COUNT(*)         FROM CLTB_ACCOUNT_COMPONENTS   UNION ALL
SELECT 'CLTB_ACCOUNT_SCHEDULES'     , COUNT(*)         FROM CLTB_ACCOUNT_SCHEDULES
ORDER BY 2 DESC;

PROMPT
PROMPT ##############################################################################
PROMPT # SECTION 2 - EXPLORATION DE STRUCTURE
PROMPT ##############################################################################

-- 2.1 Colonnes detaillees des tables cles (type, taille, nullable)
PROMPT
PROMPT --- 2.1 Colonnes des tables cles ---
SELECT  c.table_name,
        c.column_id        AS pos,
        c.column_name,
        c.data_type,
        c.data_length,
        c.data_precision,
        c.data_scale,
        c.nullable,
        c.data_default
FROM    user_tab_columns c
WHERE   c.table_name IN (
            'STTM_CUSTOMER','STTM_CUST_PERSONAL','STTM_CUST_ACCOUNT',
            'STTB_ACCOUNT','STTM_ACCOUNT_CLASS','STTM_CUSTOMER_CAT',
            'STTM_KYC_MASTER','STTM_KYC_RETAIL','STTM_KYC_CORPORATE',
            'STTM_KYC_CORP_KEYPERSONS')
ORDER BY c.table_name, c.column_id;

-- 2.2 Commentaires de colonnes (semantique metier)
PROMPT
PROMPT --- 2.2 Commentaires de colonnes ---
SELECT  cc.table_name, cc.column_name, cc.comments
FROM    user_col_comments cc
WHERE   cc.table_name IN (
            'STTM_CUSTOMER','STTM_CUST_PERSONAL','STTM_CUST_ACCOUNT',
            'STTB_ACCOUNT','STTM_ACCOUNT_CLASS','STTM_CUSTOMER_CAT',
            'STTM_KYC_MASTER','STTM_KYC_RETAIL','STTM_KYC_CORPORATE',
            'STTM_KYC_CORP_KEYPERSONS')
   AND  cc.comments IS NOT NULL
ORDER BY cc.table_name, cc.column_name;

-- 2.3 Cles primaires et uniques
PROMPT
PROMPT --- 2.3 Cles primaires / uniques ---
SELECT  uc.table_name,
        uc.constraint_name,
        uc.constraint_type,             -- P=Primary, U=Unique, R=FK, C=Check
        LISTAGG(ucc.column_name,',')
            WITHIN GROUP (ORDER BY ucc.position) AS columns
FROM    user_constraints  uc
JOIN    user_cons_columns ucc
        ON ucc.constraint_name = uc.constraint_name
WHERE   uc.table_name IN (
            'STTM_CUSTOMER','STTM_CUST_PERSONAL','STTM_CUST_ACCOUNT',
            'STTB_ACCOUNT','STTM_ACCOUNT_CLASS','STTM_CUSTOMER_CAT',
            'STTM_KYC_MASTER','STTM_KYC_RETAIL','STTM_KYC_CORPORATE',
            'STTM_KYC_CORP_KEYPERSONS')
   AND  uc.constraint_type IN ('P','U')
GROUP BY uc.table_name, uc.constraint_name, uc.constraint_type
ORDER BY uc.table_name, uc.constraint_type;

-- 2.4 Cles etrangeres declarees
PROMPT
PROMPT --- 2.4 Cles etrangeres ---
SELECT  uc.table_name              AS child_table,
        uc.constraint_name,
        LISTAGG(ucc.column_name,',')
           WITHIN GROUP (ORDER BY ucc.position) AS child_columns,
        rc.table_name              AS parent_table,
        LISTAGG(rcc.column_name,',')
           WITHIN GROUP (ORDER BY rcc.position) AS parent_columns
FROM    user_constraints  uc
JOIN    user_cons_columns ucc ON ucc.constraint_name = uc.constraint_name
JOIN    user_constraints  rc  ON rc.constraint_name  = uc.r_constraint_name
JOIN    user_cons_columns rcc ON rcc.constraint_name = rc.constraint_name
                              AND rcc.position       = ucc.position
WHERE   uc.constraint_type = 'R'
   AND  uc.table_name IN (
            'STTM_CUSTOMER','STTM_CUST_PERSONAL','STTM_CUST_ACCOUNT',
            'STTB_ACCOUNT','STTM_ACCOUNT_CLASS','STTM_CUSTOMER_CAT',
            'STTM_KYC_MASTER','STTM_KYC_RETAIL','STTM_KYC_CORPORATE',
            'STTM_KYC_CORP_KEYPERSONS')
GROUP BY uc.table_name, uc.constraint_name, rc.table_name
ORDER BY uc.table_name;

-- 2.5 Index disponibles (utile pour optimiser les requetes futures)
PROMPT
PROMPT --- 2.5 Index sur les tables cibles ---
SELECT  i.table_name,
        i.index_name,
        i.uniqueness,
        i.status,
        LISTAGG(ic.column_name,',')
           WITHIN GROUP (ORDER BY ic.column_position) AS index_columns
FROM    user_indexes      i
JOIN    user_ind_columns  ic ON ic.index_name = i.index_name
WHERE   i.table_name IN (
            'STTM_CUSTOMER','STTM_CUST_PERSONAL','STTM_CUST_ACCOUNT',
            'STTB_ACCOUNT','STTM_ACCOUNT_CLASS','STTM_CUSTOMER_CAT',
            'STTM_KYC_MASTER','STTM_KYC_RETAIL','STTM_KYC_CORPORATE',
            'STTM_KYC_CORP_KEYPERSONS')
GROUP BY i.table_name, i.index_name, i.uniqueness, i.status
ORDER BY i.table_name, i.uniqueness DESC;

-- 2.6 Resume : nombre de colonnes / nombre d'index par table
PROMPT
PROMPT --- 2.6 Resume volumetrique structure ---
SELECT  t.table_name,
        t.num_rows,
        (SELECT COUNT(*) FROM user_tab_columns c WHERE c.table_name = t.table_name) AS nb_cols,
        (SELECT COUNT(*) FROM user_indexes     i WHERE i.table_name = t.table_name) AS nb_idx,
        (SELECT COUNT(*) FROM user_constraints u
          WHERE u.table_name = t.table_name AND u.constraint_type='P')              AS has_pk
FROM    user_tables t
WHERE   t.table_name IN (
            'STTM_CUSTOMER','STTM_CUST_PERSONAL','STTM_CUST_ACCOUNT',
            'STTB_ACCOUNT','STTM_ACCOUNT_CLASS','STTM_CUSTOMER_CAT',
            'STTM_KYC_MASTER','STTM_KYC_RETAIL','STTM_KYC_CORPORATE',
            'STTM_KYC_CORP_KEYPERSONS')
ORDER BY t.num_rows DESC NULLS LAST;

PROMPT
PROMPT ##############################################################################
PROMPT # SECTION 3 - PROFILING DES DONNEES
PROMPT ##############################################################################

-- 3.1 STTM_CUSTOMER : volumetrie + qualite des champs cles
PROMPT
PROMPT --- 3.1 STTM_CUSTOMER : qualite des champs cles ---
SELECT  COUNT(*)                                                          AS total_rows,
        COUNT(DISTINCT customer_no)                                       AS dist_customer_no,
        COUNT(*) - COUNT(customer_no)                                     AS null_customer_no,
        COUNT(DISTINCT unique_id_value)                                   AS dist_unique_id,
        COUNT(*) - COUNT(unique_id_value)                                 AS null_unique_id,
        COUNT(DISTINCT kyc_ref_no)                                        AS dist_kyc_ref,
        COUNT(*) - COUNT(kyc_ref_no)                                      AS null_kyc_ref,
        COUNT(DISTINCT liability_no)                                      AS dist_liability_no,
        SUM(CASE WHEN customer_name1 IS NULL OR TRIM(customer_name1)='' THEN 1 ELSE 0 END) AS null_name,
        SUM(CASE WHEN short_name     IS NULL OR TRIM(short_name)='' THEN 1 ELSE 0 END)     AS null_short_name,
        SUM(CASE WHEN nationality    IS NULL THEN 1 ELSE 0 END)                            AS null_nationality
FROM    STTM_CUSTOMER;

-- 3.2 STTM_CUST_PERSONAL : qualite des donnees personnes physiques
PROMPT
PROMPT --- 3.2 STTM_CUST_PERSONAL : qualite ---
SELECT  COUNT(*)                                                          AS total_rows,
        COUNT(DISTINCT customer_no)                                       AS dist_customer_no,
        COUNT(DISTINCT p_national_id)                                     AS dist_national_id,
        COUNT(*) - COUNT(p_national_id)                                   AS null_national_id,
        COUNT(DISTINCT passport_no)                                       AS dist_passport,
        SUM(CASE WHEN first_name    IS NULL OR TRIM(first_name)='' THEN 1 ELSE 0 END) AS null_first_name,
        SUM(CASE WHEN last_name     IS NULL OR TRIM(last_name)='' THEN 1 ELSE 0 END)  AS null_last_name,
        SUM(CASE WHEN date_of_birth IS NULL THEN 1 ELSE 0 END)                        AS null_dob,
        SUM(CASE WHEN sex           IS NULL THEN 1 ELSE 0 END)                        AS null_sex,
        SUM(CASE WHEN e_mail        IS NULL THEN 1 ELSE 0 END)                        AS null_email,
        SUM(CASE WHEN mobile_number IS NULL THEN 1 ELSE 0 END)                        AS null_mobile
FROM    STTM_CUST_PERSONAL;

-- 3.3 STTM_CUST_ACCOUNT : qualite cote comptes
PROMPT
PROMPT --- 3.3 STTM_CUST_ACCOUNT : qualite ---
SELECT  COUNT(*)                                                          AS total_rows,
        COUNT(DISTINCT cust_ac_no)                                        AS dist_cust_ac_no,
        COUNT(DISTINCT cust_no)                                           AS dist_cust_no,
        COUNT(DISTINCT iban_ac_no)                                        AS dist_iban,
        COUNT(*) - COUNT(cust_ac_no)                                      AS null_account_no,
        COUNT(*) - COUNT(cust_no)                                         AS null_cust_no,
        SUM(CASE WHEN ac_desc       IS NULL OR TRIM(ac_desc)='' THEN 1 ELSE 0 END)  AS null_ac_desc,
        SUM(CASE WHEN ccy           IS NULL THEN 1 ELSE 0 END)                      AS null_ccy,
        SUM(CASE WHEN branch_code   IS NULL THEN 1 ELSE 0 END)                      AS null_branch,
        SUM(CASE WHEN account_class IS NULL THEN 1 ELSE 0 END)                      AS null_acclass,
        SUM(CASE WHEN ac_open_date  IS NULL THEN 1 ELSE 0 END)                      AS null_open_date
FROM    STTM_CUST_ACCOUNT;

-- 3.4 STTB_ACCOUNT : table comptable (GL + comptes clients)
PROMPT
PROMPT --- 3.4 STTB_ACCOUNT : qualite ---
SELECT  COUNT(*)                                                          AS total_rows,
        COUNT(DISTINCT ac_gl_no)                                          AS dist_ac_gl_no,
        COUNT(DISTINCT cust_no)                                           AS dist_cust_no,
        SUM(CASE WHEN ac_or_gl='A' THEN 1 ELSE 0 END)                     AS nb_accounts,
        SUM(CASE WHEN ac_or_gl='G' THEN 1 ELSE 0 END)                     AS nb_gls,
        SUM(CASE WHEN cust_no   IS NULL AND ac_or_gl='A' THEN 1 ELSE 0 END) AS account_without_cust
FROM    STTB_ACCOUNT;

-- 3.5 STTM_KYC_MASTER : couverture KYC
PROMPT
PROMPT --- 3.5 STTM_KYC_MASTER : qualite ---
SELECT  COUNT(*)                                                          AS total_rows,
        COUNT(DISTINCT kyc_ref_no)                                        AS dist_kyc_ref,
        COUNT(*) - COUNT(kyc_ref_no)                                      AS null_kyc_ref,
        SUM(CASE WHEN risk_level    IS NULL THEN 1 ELSE 0 END)            AS null_risk_level,
        SUM(CASE WHEN kyc_cust_type IS NULL THEN 1 ELSE 0 END)            AS null_cust_type
FROM    STTM_KYC_MASTER;

-- 3.6 STTM_KYC_RETAIL & STTM_KYC_CORPORATE : repartition
PROMPT
PROMPT --- 3.6 KYC RETAIL : qualite ---
SELECT  COUNT(*)                                                          AS total_rows,
        COUNT(DISTINCT kyc_ref_no)                                        AS dist_kyc_ref,
        SUM(CASE WHEN birth_date  IS NULL THEN 1 ELSE 0 END)              AS null_birth,
        SUM(CASE WHEN nationality IS NULL THEN 1 ELSE 0 END)              AS null_nat,
        SUM(CASE WHEN passport_no IS NULL THEN 1 ELSE 0 END)              AS null_passport,
        SUM(CASE WHEN total_income IS NULL OR total_income = 0 THEN 1 ELSE 0 END) AS null_or_zero_income
FROM    STTM_KYC_RETAIL;

PROMPT
PROMPT --- 3.7 KYC CORPORATE : qualite ---
SELECT  COUNT(*)                                                          AS total_rows,
        COUNT(DISTINCT kyc_ref_no)                                        AS dist_kyc_ref,
        SUM(CASE WHEN company_type    IS NULL THEN 1 ELSE 0 END)          AS null_company_type,
        SUM(CASE WHEN trade_licence_no IS NULL THEN 1 ELSE 0 END)         AS null_trade_lic,
        SUM(CASE WHEN annual_turnover IS NULL OR annual_turnover = 0 THEN 1 ELSE 0 END) AS null_or_zero_turnover
FROM    STTM_KYC_CORPORATE;

-- 3.8 Profiling generique : top tables par taux de NULL sur colonnes critiques
PROMPT
PROMPT --- 3.8 Synthese qualite (taux de remplissage des colonnes cles) ---
WITH src AS (
    SELECT 'STTM_CUSTOMER'      AS tbl, 'CUSTOMER_NO'  AS col, COUNT(*) AS tot, COUNT(customer_no)   AS notnull FROM STTM_CUSTOMER
    UNION ALL SELECT 'STTM_CUSTOMER',     'UNIQUE_ID_VALUE', COUNT(*), COUNT(unique_id_value)        FROM STTM_CUSTOMER
    UNION ALL SELECT 'STTM_CUSTOMER',     'KYC_REF_NO',      COUNT(*), COUNT(kyc_ref_no)             FROM STTM_CUSTOMER
    UNION ALL SELECT 'STTM_CUST_PERSONAL','P_NATIONAL_ID',   COUNT(*), COUNT(p_national_id)          FROM STTM_CUST_PERSONAL
    UNION ALL SELECT 'STTM_CUST_PERSONAL','PASSPORT_NO',     COUNT(*), COUNT(passport_no)            FROM STTM_CUST_PERSONAL
    UNION ALL SELECT 'STTM_CUST_PERSONAL','DATE_OF_BIRTH',   COUNT(*), COUNT(date_of_birth)          FROM STTM_CUST_PERSONAL
    UNION ALL SELECT 'STTM_CUST_ACCOUNT', 'CUST_AC_NO',      COUNT(*), COUNT(cust_ac_no)             FROM STTM_CUST_ACCOUNT
    UNION ALL SELECT 'STTM_CUST_ACCOUNT', 'CUST_NO',         COUNT(*), COUNT(cust_no)                FROM STTM_CUST_ACCOUNT
    UNION ALL SELECT 'STTM_CUST_ACCOUNT', 'IBAN_AC_NO',      COUNT(*), COUNT(iban_ac_no)             FROM STTM_CUST_ACCOUNT
)
SELECT  tbl,
        col,
        tot,
        notnull,
        tot-notnull                                              AS nb_null,
        ROUND( (tot-notnull) * 100 / NULLIF(tot,0), 2)           AS pct_null
FROM    src
ORDER BY tbl, col;
