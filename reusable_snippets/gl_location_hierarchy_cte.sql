/* Resolves a GL accounting-flexfield location tree into
   child location -> parent location (region), so any report can show Region.

   Replace 'Location Tree' with your tree code, and the NOT IN list with the
   top-level nodes you want to skip. Then bridge an organization to this CTE
   through XLA_MAPPING_SET_VALUES (INPUT_VALUE_CONSTANT1 = organization id,
   VALUE_CONSTANT = location segment). */

WITH cte_regions AS (
    SELECT DISTINCT
        V.VALUE        AS LOCATION_SEGMENT,
        V.DESCRIPTION  AS LOCATION_NAME,
        VP.VALUE       AS PARENT_LOCATION_SEGMENT,
        VP.DESCRIPTION AS PARENT_LOCATION_NAME
    FROM FND_TREE_NODE TN
    JOIN FND_VS_VALUES_VL V
        ON TN.PK1_START_VALUE = V.VALUE
       AND V.ATTRIBUTE_CATEGORY = 'Location Tree'
    JOIN FND_VS_VALUES_VL VP
        ON TN.PARENT_PK1_VALUE = VP.VALUE
       AND VP.ATTRIBUTE_CATEGORY = 'Location Tree'
    JOIN FND_TREE_VERSION TV
        ON TN.TREE_VERSION_ID = TV.TREE_VERSION_ID
    JOIN FND_VS_VALUE_SETS VS
        ON VP.VALUE_SET_ID = VS.VALUE_SET_ID
    WHERE TN.TREE_STRUCTURE_CODE = 'GL_ACCT_FLEX'
      AND TN.TREE_CODE = 'Location Tree'
      AND TN.PARENT_PK1_VALUE IS NOT NULL
      AND VP.VALUE NOT IN ('TOP_NODE_1', 'TOP_NODE_2')
)
SELECT * FROM cte_regions
