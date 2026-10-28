SELECT q.*,
       CASE
         WHEN q.PRINTING_ORIGINAL_DATE IS NOT NULL THEN
              COALESCE(TRIM(q.TRX_EMAIL_RECIPIENTS),
                       TRIM(q.BILL_TO_CONTACT_EMAIL),
                       TRIM(q.SITE_BILL_TO_EMAILS))
       END AS EMAILED_TO,
       CASE
         WHEN q.PRINTING_ORIGINAL_DATE IS NULL          THEN 'Not Sent'
         WHEN TRIM(q.TRX_EMAIL_RECIPIENTS)  IS NOT NULL THEN 'Invoice'
         WHEN TRIM(q.BILL_TO_CONTACT_EMAIL) IS NOT NULL THEN 'Bill-To Contact'
         WHEN TRIM(q.SITE_BILL_TO_EMAILS)   IS NOT NULL THEN 'Site Default'
         ELSE 'No Email on File'
       END AS EMAILED_TO_SOURCE
FROM (
    SELECT
        APSA.TRX_NUMBER AS documentNumber,
        apsa.customer_id,
        APSA.AMOUNT_DUE_ORIGINAL AS OrignalDocumentAmount,
        APSA.AMOUNT_DUE_REMAINING AS Current_amount,
        APSA.NUMBER_OF_DUE_DATES,
        TO_CHAR(APSA.DUE_DATE,'MM/DD/YYYY') AS DUE_DATE,
        TO_CHAR(APSA.TRX_DATE,'MM/DD/YYYY') AS Document_DATE,
        TO_CHAR(RCTA.PRINTING_ORIGINAL_DATE,'MM/DD/YYYY') AS Date_Sent,
        CASE
            WHEN RCTTA.type = 'CM' THEN 'Credit/Payment'
            WHEN APSA.STATUS = 'CL' THEN 'Credit/Payment'
            WHEN APSA.STATUS = 'OP' AND APSA.DUE_DATE >= SYSDATE THEN 'Current'
            WHEN APSA.STATUS = 'OP' AND APSA.DUE_DATE < SYSDATE THEN 'Past Due'
            ELSE APSA.STATUS
        END AS STATUS,
        RCTTA.NAME,
        RCTTA.description,
        RCTTA.type AS TYPE_CODE,
        CASE
            WHEN RCTTA.type = 'INV' THEN 'Invoice'
            WHEN RCTTA.type = 'CM' THEN 'Credit Memo'
            WHEN RCTTA.type = 'DM' THEN 'Debit Memo'
            ELSE RCTTA.type
        END AS type,
        RCTTA.default_term,
        rtb.name AS term_name,
        CASE
            WHEN RCTTA.type = 'CM' THEN 'Credit/Payment'
            WHEN APSA.STATUS = 'OP' THEN
                CASE
                    WHEN APSA.DUE_DATE > SYSDATE THEN
                        CASE
                            WHEN APSA.DUE_DATE <= SYSDATE + 7 THEN '<7 Days Until Due'
                            WHEN APSA.DUE_DATE <= SYSDATE + 14 THEN '7-14 Days Until Due'
                            WHEN APSA.DUE_DATE <= SYSDATE + 20 THEN '15-20 Days Until Due'
                            ELSE '21+ Days Until Due'
                        END
                    WHEN APSA.DUE_DATE <= SYSDATE THEN
                        CASE
                            WHEN APSA.DUE_DATE >= SYSDATE - 15 THEN '0-15 Days Past Due'
                            WHEN APSA.DUE_DATE >= SYSDATE - 30 THEN '16-30 Days Past Due'
                            WHEN APSA.DUE_DATE >= SYSDATE - 60 THEN '31-60 Days Past Due'
                            WHEN APSA.DUE_DATE >= SYSDATE - 90 THEN '61-90 Days Past Due'
                            ELSE '90+ Days Past Due'
                        END
                END
            ELSE 'Credit/Payment'
        END AS date_range,
        CASE
            WHEN APSA.STATUS = 'OP' AND APSA.DUE_DATE < SYSDATE AND APSA.AMOUNT_DUE_REMAINING > 0
            THEN TRUNC(SYSDATE - APSA.DUE_DATE)
            ELSE NULL
        END AS PastDaysDueDate,
        HOP.EXTN_ATTRIBUTE_CHAR039 CRM_ACCOUNT_ID,
        HOP.EXTN_ATTRIBUTE_CHAR036 ACCOUNT_NICHE,
        hz.PARTY_NAME ACCOUNT,
        ZBAHV.DEP9_PARTY_NAME Parent_Name,
        HL_REGION.meaning Region,
        rcta.PRIMARY_RESOURCE_SALESREP_ID,
        hzm.PARTY_NAME AS Manager,
        hl.ADDRESS1 AS billing_address,
        hl.ADDRESS2 AS billing_address2,
        hl.city AS City,
        hl.state AS States,
        hl.province AS Province,
        hl.postal_code AS PostalCode,
        RCTA.PRINTING_ORIGINAL_DATE,
        HPS.PARTY_SITE_NAME,
        RCTA.PURCHASE_ORDER AS PO_NUMBER,
        RCTA.DEL_CONTACT_EMAIL_ADDRESS AS TRX_EMAIL_RECIPIENTS,
        per.PARTY_NAME AS BILL_TO_CONTACT,
        NVL(per.EMAIL_ADDRESS,
            (SELECT MAX(hcp.EMAIL_ADDRESS)
               FROM HZ_CONTACT_POINTS hcp
              WHERE hcp.OWNER_TABLE_NAME   = 'HZ_PARTIES'
                AND hcp.OWNER_TABLE_ID     = hcar.CONTACT_PERSON_ID
                AND hcp.CONTACT_POINT_TYPE = 'EMAIL'
                AND hcp.STATUS             = 'A')
        ) AS BILL_TO_CONTACT_EMAIL,
        (SELECT LISTAGG(sp.EMAIL_ADDRESS, '; ')
                  WITHIN GROUP (ORDER BY sp.EMAIL_ADDRESS)
           FROM HZ_CUST_ACCOUNT_ROLES sr
           JOIN HZ_ROLE_RESPONSIBILITY srr
             ON srr.CUST_ACCOUNT_ROLE_ID = sr.CUST_ACCOUNT_ROLE_ID
            AND srr.RESPONSIBILITY_TYPE  = 'BILL_TO'
           JOIN HZ_PARTIES sp ON sp.PARTY_ID = sr.CONTACT_PERSON_ID
          WHERE sr.CUST_ACCT_SITE_ID = hcsu.CUST_ACCT_SITE_ID
            AND sr.STATUS = 'A'
            AND sp.EMAIL_ADDRESS IS NOT NULL
        ) AS SITE_BILL_TO_EMAILS,
        HPS.PARTY_SITE_NAME   AS BILL_TO_SITE_NAME,
        HPS.PARTY_SITE_NUMBER AS BILL_TO_SITE_NUMBER,
        hcsu.LOCATION         AS BILL_TO_LOCATION
    FROM AR_PAYMENT_SCHEDULES_ALL APSA
    INNER JOIN RA_CUST_TRX_TYPES_ALL RCTTA ON RCTTA.CUST_TRX_TYPE_SEQ_ID = APSA.CUST_TRX_TYPE_SEQ_ID
    LEFT  JOIN ra_terms_vl rtb ON rtb.TERM_ID = APSA.TERM_ID
    INNER JOIN HZ_CUST_ACCOUNTS accounts ON accounts.cust_account_id = apsa.customer_id
    INNER JOIN hz_parties hz ON hz.party_id = accounts.party_id
    INNER JOIN ZCA_BI_ACCOUNT_HIERARCHIES_V ZBAHV ON ZBAHV.DEP0_PK1_VALUE = hz.party_id
    INNER JOIN ra_customer_trx_all rcta ON rcta.CUSTOMER_TRX_ID = apsa.CUSTOMER_TRX_ID
    LEFT  JOIN HZ_ORGANIZATION_PROFILES HOP ON HOP.party_id = hz.party_id
    INNER JOIN hz_parties hzm ON HOP.owner_party_id = hzm.party_id
    LEFT  JOIN HZ_LOOKUPS HL_REGION ON HOP.EXTN_ATTRIBUTE_CHAR020 = HL_REGION.LOOKUP_CODE
                                   AND HL_REGION.LOOKUP_TYPE = 'CUSTOM_ACCOUNT_REGION'
    LEFT  JOIN HZ_CUST_SITE_USES_ALL hcsu ON rcta.BILL_TO_SITE_USE_ID = hcsu.SITE_USE_ID
    LEFT  JOIN HZ_CUST_ACCT_SITES_ALL hcas ON hcsu.CUST_ACCT_SITE_ID = hcas.CUST_ACCT_SITE_ID
    LEFT  JOIN HZ_PARTY_SITES hps ON hcas.PARTY_SITE_ID = hps.PARTY_SITE_ID
    LEFT  JOIN HZ_LOCATIONS hl ON hps.LOCATION_ID = hl.LOCATION_ID
    LEFT  JOIN HZ_CUST_ACCOUNT_ROLES hcar ON hcar.CUST_ACCOUNT_ROLE_ID = RCTA.BILL_TO_CONTACT_ID
    LEFT  JOIN HZ_PARTIES per ON per.PARTY_ID = hcar.CONTACT_PERSON_ID
    WHERE (HL_REGION.meaning = (:P_Region) OR 'ALL' = (:P_Region||'ALL'))
      AND (hzm.PARTY_NAME = (:P_am) OR 'ALL' = (:P_am||'ALL'))
      AND APSA.AMOUNT_DUE_REMAINING <> 0
      AND (ZBAHV.DEP9_PARTY_NAME = (:P_Parent) OR 'ALL' = (:P_Parent||'ALL'))
      AND (hz.PARTY_NAME = (:P_Account) OR 'ALL' = (:P_Account||'ALL'))
) q
