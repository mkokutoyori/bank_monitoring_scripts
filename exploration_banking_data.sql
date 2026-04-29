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
