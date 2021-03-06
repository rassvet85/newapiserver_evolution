/*Oracle 12 - вывод всех клиентов TNG*/
/*Таблица ТA - выбор всех пользователей, у которых есть хотя бы одна действующая услуга, где EXPDATE - окончание услуги, VALID_TILL - срок действия карточки */
WITH TA AS
         (
             SELECT SUBX.CARD_ID,
                    CARDS.VALID_TILL,
                    MAX(CASE
                            WHEN SUBX.status = 2 THEN
                                CASE
                                    WHEN SUBX.IS_MEMBERSHIP = 0 THEN SUBX.expiration_date + 1
                                    ELSE
                                        CASE
                                            WHEN SUBX.expiration_date > SUBX.mmshp_end_date
                                                THEN SUBX.expiration_date + 1
                                            ELSE SUBX.mmshp_end_date + 1
                                            END
                                    END
                            ELSE
                                CASE
                                    WHEN SUBX.expiration_date >= TRUNC(current_date) OR
                                         SUBX.mmshp_end_date >= TRUNC(current_date)
                                        THEN TRUNC(current_date)
                                    ELSE
                                        CASE
                                            WHEN (SUBX.expiration_date > SUBX.mmshp_end_date OR
                                                  SUBX.mmshp_end_date IS NULL) THEN SUBX.expiration_date + 1
                                            ELSE SUBX.mmshp_end_date + 1
                                            END
                                    END
                        END) as EXPDATE
             FROM SUBSCRIPTION_ACCOUNTING SUBX
                      LEFT JOIN CARDS ON CARDS.CARD_ID = SUBX.CARD_ID
             WHERE CARDS.magstripe IS NOT NULL
               AND CARDS.CARD_STATUS_ID = 1
               AND length(CARDS.magstripe) = 8
               AND (SUBX.mmshp_end_date > ADD_MONTHS(CURRENT_DATE, -12) OR
                    SUBX.expiration_date > ADD_MONTHS(CURRENT_DATE, -12))
             GROUP BY SUBX.CARD_ID, CARDS.VALID_TILL
         ),
/*Таблица Т1 - NAMECARD - описание усгуг пользователя */
     T1 AS
         (
             SELECT SUBX.CARD_ID,
                    CAST((listagg(CASE
                                      WHEN MITMSX.NAME1 IS NOT NULL THEN convert(
                                                  CASE WHEN SUBX.STATUS = 3 THEN 'Услуга ЗАМОРОЖЕНА' || chr(10) END ||
                                                  MITMSX.NAME1 || ' (Срок действия: ' ||
                                                  TO_CHAR(SUBX.EXPIRATION_DATE, 'DD.MM.YYYY') || ')' || chr(10) ||
                                                  CASE
                                                      WHEN SUBITEMSX.CHARGE_POLICY = 2
                                                          THEN '- осталось дней заморозки: '
                                                      ELSE '- осталось посещений: '
                                                      END
                                                  || BALX.COUNT, 'UTF8') END, chr(10))
                                  within group (order by MITMSX.NAME1)) AS NVARCHAR2(2000)) AS NAMECARD
             FROM SUBSCRIPTION_ACCOUNTING SUBX
                      LEFT JOIN MENU_ITEMS MITMSX ON SUBX.SUBSCRIPTION_MI_ID = MITMSX.MI_ID
                      LEFT JOIN ITEM_BALANCE BALX ON SUBX.SUBSCRIPTION_ACCOUNTING_ID = BALX.SUBSCRIPTION_ACCOUNTING_ID
                      LEFT JOIN SUBSCRIPTION_ITEMS SUBITEMSX
                                ON SUBITEMSX.SUBSCRIPTION_ITEM_ID = BALX.SUBSCRIPTION_ITEM_ID
             WHERE SUBX.SUBSCRIPTION_MI_ID <> 7950
               AND (SUBX.STATUS = 2 OR SUBX.STATUS = 3)
             GROUP BY SUBX.CARD_ID
         ),
/*Таблица Т2 - здесь происходит выбор пользователей с типом карты 5335 (сопровождающий). Время действия карты - зависит от времени действия карт сопровождаемых. */
     T2 AS
         (
             SELECT CARD_ID,
                    MAX(EXPDATE)                                                        AS EXPDATE,
                    listagg(convert(DESC1, 'UTF8'), ', ') within group (order by DESC1) AS DESCR
             FROM (
                      (SELECT CARDSX.CARD_ID                                    AS CARD_ID,
                              CASE
                                  WHEN CARDS.LAST_NAME IS NOT NULL THEN CARDS.LAST_NAME || ' ' || CARDS.FIRST_NAME ||
                                                                        ' (' || CLRLX.RELATION_1 || ', ' ||
                                                                        TO_CHAR(TA.EXPDATE - 1, 'DD.MM.YYYY') ||
                                                                        ')' END AS DESC1,
                              TA.EXPDATE
                       FROM CARDS
                                LEFT JOIN CLIENT_RELATIONS CLRLX
                                          ON CARDS.CARD_ID = CLRLX.CARD_ID_1 AND CLRLX.CARD_ID_1 != CLRLX.CARD_ID_2
                                LEFT JOIN TA ON TA.CARD_ID = CARDS.CARD_ID
                                LEFT JOIN CARDS CARDSX ON CARDSX.CARD_ID = CLRLX.CARD_ID_2
                       WHERE CARDS.CARD_TYPE_ID <> 5335
                         AND CARDSX.CARD_TYPE_ID = 5335
                         AND CLRLX.CARD_ID_1 IS NOT NULL)

                      UNION

                      (SELECT CARDSY.CARD_ID                                    AS CARD_ID,
                              CASE
                                  WHEN CARDS.LAST_NAME IS NOT NULL THEN CARDS.LAST_NAME || ' ' || CARDS.FIRST_NAME ||
                                                                        ' (' || CLRLY.RELATION_2 || ', ' ||
                                                                        TO_CHAR(TA.EXPDATE - 1, 'DD.MM.YYYY') ||
                                                                        ')' END AS DESC1,
                              TA.EXPDATE
                       FROM CARDS
                                LEFT JOIN CLIENT_RELATIONS CLRLY
                                          ON CARDS.CARD_ID = CLRLY.CARD_ID_2 AND CLRLY.CARD_ID_1 != CLRLY.CARD_ID_2
                                LEFT JOIN TA ON TA.CARD_ID = CARDS.CARD_ID
                                LEFT JOIN CARDS CARDSY ON CARDSY.CARD_ID = CLRLY.CARD_ID_1
                       WHERE CARDS.CARD_TYPE_ID <> 5335
                         AND CARDSY.CARD_TYPE_ID = 5335
                         AND CLRLY.CARD_ID_2 IS NOT NULL)

                      UNION

                      (SELECT 10000000 + CARDEXTRA.ID                           AS CARD_ID,
                              CASE
                                  WHEN CARDS.LAST_NAME IS NOT NULL THEN CARDS.LAST_NAME || ' ' || CARDS.FIRST_NAME ||
                                                                        ' (' || CLRLX.RELATION_1 || ', ' ||
                                                                        TO_CHAR(TA.EXPDATE - 1, 'DD.MM.YYYY') ||
                                                                        ')' END AS DESC1,
                              TA.EXPDATE
                       FROM CARDS
                                LEFT JOIN CLIENT_RELATIONS CLRLX
                                          ON CARDS.CARD_ID = CLRLX.CARD_ID_1 AND CLRLX.CARD_ID_1 != CLRLX.CARD_ID_2
                                LEFT JOIN TA ON TA.CARD_ID = CARDS.CARD_ID
                                LEFT JOIN CARD_XTRA CARDEXTRA ON CARDEXTRA.CARD_ID = CLRLX.CARD_ID_2
                       WHERE CARDS.CARD_TYPE_ID <> 5335
                         AND CARDEXTRA.CARD_TYPE_ID = 5335
                         AND CARDEXTRA.DELETE_DATE IS NULL)

                      UNION

                      (SELECT 10000000 + CARDEXTRA.ID                           AS CARD_ID,
                              CASE
                                  WHEN CARDS.LAST_NAME IS NOT NULL THEN CARDS.LAST_NAME || ' ' || CARDS.FIRST_NAME ||
                                                                        ' (' || CLRLY.RELATION_2 || ', ' ||
                                                                        TO_CHAR(TA.EXPDATE - 1, 'DD.MM.YYYY') ||
                                                                        ')' END AS DESC1,
                              TA.EXPDATE
                       FROM CARDS
                                LEFT JOIN CLIENT_RELATIONS CLRLY
                                          ON CARDS.CARD_ID = CLRLY.CARD_ID_2 AND CLRLY.CARD_ID_1 != CLRLY.CARD_ID_2
                                LEFT JOIN TA ON TA.CARD_ID = CARDS.CARD_ID
                                LEFT JOIN CARD_XTRA CARDEXTRA ON CARDEXTRA.CARD_ID = CLRLY.CARD_ID_1
                       WHERE CARDS.CARD_TYPE_ID <> 5335
                         AND CARDEXTRA.CARD_TYPE_ID = 5335
                         AND CARDEXTRA.DELETE_DATE IS NULL)
                  )
             WHERE EXPDATE IS NOT NULL
             GROUP BY CARD_ID
         ),
/*Таблица ТB - сводная таблица из пользователей различных типов */
     TB AS
         (
             SELECT CARDS1.last_name || ' ' || CARDS1.first_name || ' ' || CARDS1.second_name AS FULL_NAME,
                    CARDS1.card_id                                                            as CARD_ID1,
                    CARDS1.magstripe                                                          as MAGSTR,
                    CTYP.TYPE_NAME                                                            as COMM,
                    CARDS1.card_id                                                            as FOTO_ID,
                    CARDS1.CARD_TYPE_ID                                                       AS TYPEID,
                    CASE
                        WHEN TA.VALID_TILL IS NOT NULL AND TA.VALID_TILL + 1 < TA.EXPDATE THEN TA.VALID_TILL + 1
                        ELSE TA.EXPDATE END                                                   AS EXP_DATE
             FROM TA
                      INNER JOIN CARDS CARDS1 ON CARDS1.CARD_ID = TA.CARD_ID AND CARDS1.CARD_TYPE_ID <> 5335
                      LEFT JOIN CARD_TYPES CTYP ON CTYP.CARD_TYPE_ID = CARDS1.CARD_TYPE_ID

             UNION

             SELECT CARDS1.last_name || ' ' || CARDS1.first_name || ' ' || CARDS1.second_name AS FULL_NAME,
                    CARDS1.card_id                                                            as CARD_ID1,
                    CARDS1.magstripe                                                          as MAGSTR,
                    CTYP.TYPE_NAME                                                            as COMM,
                    CARDS1.card_id                                                            as FOTO_ID,
                    CARDS1.CARD_TYPE_ID                                                       AS TYPEID,
                    CASE
                        WHEN CARDS1.VALID_TILL IS NOT NULL AND CARDS1.VALID_TILL + 1 < T2.EXPDATE
                            THEN CARDS1.VALID_TILL + 1
                        ELSE T2.EXPDATE END                                                   AS EXP_DATE
             FROM CARDS CARDS1
                      LEFT JOIN T2 ON CARDS1.CARD_ID = T2.CARD_ID
                      LEFT JOIN CARD_TYPES CTYP ON CTYP.CARD_TYPE_ID = CARDS1.CARD_TYPE_ID
             WHERE CARDS1.CARD_TYPE_ID = 5335
               AND length(CARDS1.magstripe) = 8

             UNION

             SELECT CARDS1.last_name || ' ' || CARDS1.first_name || ' ' || CARDS1.second_name || ' (' ||
                    CTYP.TYPE_NAME || ')'   AS FULL_NAME,
                    10000000 + CARDX.ID     as CARD_ID1,
                    CARDX.magstripe         as MAGSTR,
                    CTYP.TYPE_NAME          as COMM,
                    CARDX.CARD_ID           as FOTO_ID,
                    CARDX.CARD_TYPE_ID      AS TYPEID,
                    CASE
                        WHEN CARDX.VALID_TILL IS NOT NULL AND CARDX.VALID_TILL + 1 < T2.EXPDATE
                            THEN CARDX.VALID_TILL + 1
                        ELSE T2.EXPDATE END AS EXP_DATE
             FROM CARD_XTRA CARDX
                      INNER JOIN CARDS CARDS1 ON CARDS1.CARD_ID = CARDX.CARD_ID
                      LEFT JOIN T2 ON T2.CARD_ID = 10000000 + CARDX.ID
                      LEFT JOIN CARD_TYPES CTYP ON CTYP.CARD_TYPE_ID = CARDX.CARD_TYPE_ID
             WHERE CARDX.DELETE_DATE IS NULL
               AND CARDX.CARD_TYPE_ID = 5335
               AND length(CARDX.magstripe) = 8
         )

SELECT FULL_NAME,
       CARD_ID1,
       MAGSTR,
       COMM,
       EXP_DATE,
       'TNG'                                                                    AS TNG,
       NVL(SIGUR_PHOTO_SYNC.PHOTO_VERSION, to_date('01/01/0001', 'MM/DD/YYYY')) AS PHOTO_VER,
       CASE
           WHEN TYPEID = 5335 THEN
                   CASE
                       WHEN EXP_DATE < TO_DATE(current_date, 'DD.MM.YY') THEN n'Действующие услуги отсутствуют' || (CASE
                                                                                                                        WHEN T2.DESCR IS NOT NULL
                                                                                                                            THEN chr(10) || chr(10) || n'Было сопровождение для: ' END)
                       ELSE n'карта "СОПРОВОЖДАЮЩИЙ" (Срок действия: ' || TO_CHAR(EXP_DATE - 1, 'DD.MM.YYYY') || ')' ||
                            chr(10) || chr(10) ||
                            (CASE WHEN T2.DESCR IS NOT NULL THEN n'Сопровождение для: ' END) END || T2.DESCR
           ELSE
               CASE WHEN T1.NAMECARD IS NULL THEN n'Действующие услуги отсутствуют' ELSE T1.NAMECARD END
           END                                                                  AS DESCR

FROM TB

         LEFT JOIN T1 ON T1.CARD_ID = CARD_ID1
         LEFT JOIN T2 ON T2.CARD_ID = CARD_ID1
         LEFT JOIN SIGUR_PHOTO_SYNC ON FOTO_ID = SIGUR_PHOTO_SYNC.PHOTO_ID
WHERE TB.EXP_DATE IS NOT NULL
ORDER BY EXP_DATE DESC