WITH Params AS (
    SELECT TRUNC(CAST(NVL(:P_As_Of_Date, :P_Invoice_Date_To) AS DATE)) AS As_Of_Date
      FROM DUAL
),
Bu_Ledger AS (
    SELECT FAB.BU_ID,
           FAB.BU_NAME AS Business_Unit_Name
      FROM FUN_ALL_BUSINESS_UNITS_V FAB
),
Liab_Lines AS (
    SELECT XAH.LEDGER_ID,
           COALESCE(
               CASE WHEN XDL.APPLIED_TO_ENTITY_CODE = 'AP_INVOICES'
                    THEN XDL.APPLIED_TO_SOURCE_ID_NUM_1 END,
               AID.INVOICE_ID,
               AIP.INVOICE_ID,
               AIDP.INVOICE_ID
           ) AS Invoice_Id,
           XDL.SOURCE_DISTRIBUTION_TYPE AS Src_Type,
           XDL.SOURCE_DISTRIBUTION_ID_NUM_1 AS Src_Id,
           XAL.PARTY_ID,
           XAL.PARTY_SITE_ID,
           TRUNC(XAH.ACCOUNTING_DATE) AS Gl_Date,
           NVL(XDL.UNROUNDED_ACCOUNTED_CR, 0) - NVL(XDL.UNROUNDED_ACCOUNTED_DR, 0) AS Acctd_Bal,
           NVL(XDL.UNROUNDED_ENTERED_CR, 0) - NVL(XDL.UNROUNDED_ENTERED_DR, 0) AS Entered_Bal,
           XAL.CURRENCY_CODE
      FROM XLA_AE_HEADERS XAH
      JOIN XLA_AE_LINES XAL
        ON XAL.AE_HEADER_ID = XAH.AE_HEADER_ID
       AND XAL.APPLICATION_ID = 200
      JOIN XLA_DISTRIBUTION_LINKS XDL
        ON XDL.AE_HEADER_ID = XAL.AE_HEADER_ID
       AND XDL.AE_LINE_NUM = XAL.AE_LINE_NUM
       AND XDL.APPLICATION_ID = 200
      LEFT JOIN AP_INVOICE_DISTRIBUTIONS_ALL AID
        ON XDL.SOURCE_DISTRIBUTION_TYPE = 'AP_INV_DIST'
       AND AID.INVOICE_DISTRIBUTION_ID = XDL.SOURCE_DISTRIBUTION_ID_NUM_1
      LEFT JOIN AP_PAYMENT_HIST_DISTS APHD
        ON XDL.SOURCE_DISTRIBUTION_TYPE = 'AP_PMT_DIST'
       AND APHD.PAYMENT_HIST_DIST_ID = XDL.SOURCE_DISTRIBUTION_ID_NUM_1
      LEFT JOIN AP_INVOICE_PAYMENTS_ALL AIP
        ON AIP.INVOICE_PAYMENT_ID = APHD.INVOICE_PAYMENT_ID
      LEFT JOIN AP_PREPAY_APP_DISTS APAD
        ON XDL.SOURCE_DISTRIBUTION_TYPE = 'AP_PREPAY'
       AND APAD.PREPAY_APP_DIST_ID = XDL.SOURCE_DISTRIBUTION_ID_NUM_1
      LEFT JOIN AP_INVOICE_DISTRIBUTIONS_ALL AIDP
        ON AIDP.INVOICE_DISTRIBUTION_ID = APAD.PREPAY_APP_DISTRIBUTION_ID
      CROSS JOIN Params PRM
     WHERE XAH.APPLICATION_ID = 200
       AND XAH.BALANCE_TYPE_CODE = 'A'
       AND XAH.ACCOUNTING_ENTRY_STATUS_CODE = 'F'
       AND XAH.GL_TRANSFER_STATUS_CODE = 'Y'
       AND XAH.ACCOUNTING_DATE <= PRM.As_Of_Date
       AND XAL.ACCOUNTING_CLASS_CODE = 'LIABILITY'
       AND (:P_Ledger IS NULL OR UPPER(TRIM(:P_Ledger)) = 'ALL'
            OR XAH.LEDGER_ID IN (SELECT GL1.LEDGER_ID FROM GL_LEDGERS GL1 WHERE GL1.NAME = :P_Ledger))
),
Txn_Bal AS (
    SELECT LEDGER_ID,
           Invoice_Id,
           CASE WHEN Invoice_Id IS NULL THEN Src_Type END AS Unres_Type,
           CASE WHEN Invoice_Id IS NULL THEN Src_Id END AS Unres_Id,
           MAX(PARTY_ID) AS Party_Id,
           MAX(PARTY_SITE_ID) AS Party_Site_Id,
           MAX(CURRENCY_CODE) AS Currency_Code,
           MIN(Gl_Date) AS First_Gl_Date,
           SUM(Acctd_Bal) AS Acctd_Bal,
           SUM(Entered_Bal) AS Entered_Bal
      FROM Liab_Lines
     GROUP BY LEDGER_ID,
              Invoice_Id,
              CASE WHEN Invoice_Id IS NULL THEN Src_Type END,
              CASE WHEN Invoice_Id IS NULL THEN Src_Id END
    HAVING ROUND(SUM(Acctd_Bal), 2) <> 0
),
Inv_Due AS (
    SELECT SCH.INVOICE_ID,
           MIN(TRUNC(SCH.DUE_DATE)) AS Due_Date,
           MIN(SCH.PAYMENT_NUM) KEEP (DENSE_RANK FIRST ORDER BY SCH.DUE_DATE, SCH.PAYMENT_NUM) AS Installment_Number
      FROM AP_PAYMENT_SCHEDULES_ALL SCH
      JOIN Txn_Bal TB0
        ON TB0.Invoice_Id = SCH.INVOICE_ID
     GROUP BY SCH.INVOICE_ID
),
Base AS (
    SELECT GLL.NAME AS Ledger_Name,
           BLG.Business_Unit_Name,
           NVL(PZV.VENDOR_NAME, HZP.PARTY_NAME) AS Supplier_Name,
           PZV.SEGMENT1 AS Supplier_Number,
           PZS.VENDOR_SITE_CODE AS Supplier_Site,
           CASE WHEN TXB.Invoice_Id IS NOT NULL THEN AIA.INVOICE_TYPE_LOOKUP_CODE
                ELSE 'UNRESOLVED ' || TXB.Unres_Type
           END AS Transaction_Type,
           NVL(AIA.INVOICE_NUM, TO_CHAR(TXB.Unres_Id)) AS Invoice_Number,
           TRUNC(AIA.INVOICE_DATE) AS Invoice_Date,
           DUE.Installment_Number,
           COALESCE(DUE.Due_Date, TRUNC(AIA.INVOICE_DATE), TXB.First_Gl_Date) AS Due_Date,
           AIA.INVOICE_AMOUNT AS Invoice_Amount_Entered,
           TXB.Currency_Code,
           TXB.Entered_Bal,
           TXB.Acctd_Bal,
           PRM.As_Of_Date
      FROM Txn_Bal TXB
      JOIN GL_LEDGERS GLL
        ON GLL.LEDGER_ID = TXB.LEDGER_ID
      LEFT JOIN AP_INVOICES_ALL AIA
        ON AIA.INVOICE_ID = TXB.Invoice_Id
      LEFT JOIN Inv_Due DUE
        ON DUE.INVOICE_ID = TXB.Invoice_Id
      LEFT JOIN Bu_Ledger BLG
        ON BLG.BU_ID = AIA.ORG_ID
      LEFT JOIN POZ_SUPPLIERS_V PZV
        ON PZV.VENDOR_ID = NVL(AIA.VENDOR_ID, TXB.Party_Id)
      LEFT JOIN POZ_SUPPLIER_SITES_V PZS
        ON PZS.VENDOR_SITE_ID = NVL(AIA.VENDOR_SITE_ID, TXB.Party_Site_Id)
      LEFT JOIN HZ_PARTIES HZP
        ON HZP.PARTY_ID = AIA.PARTY_ID
      CROSS JOIN Params PRM
     WHERE (:P_Business_Unit IS NULL OR UPPER(TRIM(:P_Business_Unit)) = 'ALL'
            OR BLG.Business_Unit_Name = :P_Business_Unit)
       AND (:P_Supplier_Name IS NULL OR UPPER(TRIM(:P_Supplier_Name)) = 'ALL'
            OR UPPER(NVL(PZV.VENDOR_NAME, HZP.PARTY_NAME)) LIKE UPPER(:P_Supplier_Name) || '%')
       AND (:P_Invoice_Date_From IS NULL
            OR AIA.INVOICE_DATE >= TRUNC(CAST(:P_Invoice_Date_From AS DATE)))
       AND (:P_Invoice_Date_To IS NULL
            OR AIA.INVOICE_DATE <= TRUNC(CAST(:P_Invoice_Date_To AS DATE)))
),
Aged AS (
    SELECT B.Ledger_Name,
           B.Business_Unit_Name,
           B.Supplier_Name,
           B.Supplier_Number,
           B.Supplier_Site,
           B.Transaction_Type,
           B.Invoice_Number,
           B.Invoice_Date,
           B.Installment_Number,
           B.Due_Date,
           B.Invoice_Amount_Entered,
           B.Currency_Code,
           B.Entered_Bal,
           B.As_Of_Date,
           B.As_Of_Date - B.Due_Date AS Days_Past_Due,
           ROUND(B.Acctd_Bal, 2) AS Amt
      FROM Base B
)
SELECT Ledger_Name,
       Business_Unit_Name,
       Supplier_Name,
       Supplier_Number,
       Supplier_Site,
       Invoice_Number,
       TO_CHAR(Invoice_Date, 'FMMM/DD/YYYY') AS Invoice_Date,
       Installment_Number,
       TO_CHAR(Due_Date, 'FMMM/DD/YYYY') AS Due_Date,
       Days_Past_Due,
       Invoice_Amount_Entered,
       ROUND(Entered_Bal, 2) AS Amount_Remaining_Entered,
       CASE WHEN Days_Past_Due <= 0 THEN Amt ELSE 0 END AS Current_Amount,
       CASE WHEN Days_Past_Due BETWEEN 1 AND 30 THEN Amt ELSE 0 END AS Days_1_To_30,
       CASE WHEN Days_Past_Due BETWEEN 31 AND 60 THEN Amt ELSE 0 END AS Days_31_To_60,
       CASE WHEN Days_Past_Due BETWEEN 61 AND 90 THEN Amt ELSE 0 END AS Days_61_To_90,
       CASE WHEN Days_Past_Due > 90 THEN Amt ELSE 0 END AS Days_Over_90,
       TO_CHAR(As_Of_Date, 'FMMM/DD/YYYY') AS As_Of_Date,
       Transaction_Type,
       Currency_Code,
       Amt AS Amount_Remaining_Accounted
  FROM Aged
 ORDER BY Supplier_Name, Supplier_Site, Invoice_Number, Installment_Number
