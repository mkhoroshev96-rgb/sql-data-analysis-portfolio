-- 164. Знайди топ-5 клієнтів за сумою виторгу (revenue). Revenue = SUM(unit_price * quantity * (1 - discount))

SELECT customer_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek_per_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id
ORDER BY sum_chek_per_order DESC
LIMIT 5

-- 165. Для кожного клієнта потрібно знайти суму його першого замовлення — але не через підзапити.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,dense_rank() OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id,order_date)
SELECT *
FROM level1
WHERE rn=1

-- 166. Знайди клієнтів, які робили замовлення щонайменше 3 місяці поспіль.

WITH level1 as(SELECT DISTINCT order_date
       ,customer_id
FROM orders
JOIN order_details USING(order_id)
ORDER BY customer_id, order_date),
level2 as(SELECT customer_id
       ,order_date
	   ,date_trunc ('month', order_date) as date
       ,LEAD(order_date) OVER(partition by customer_id order by order_date) as next_date
FROM level1),
level3 as(SELECT *
       ,date_trunc ('month', next_date) as date_2
       ,LEAD(next_date) OVER(partition by customer_id order by order_date) as next_date_2
FROM level2),
level4 as(SELECT *
       ,date_trunc ('month', next_date_2) as date_3
FROM level3),
level5 as(SELECT *
       ,case when date + interval '1 month' = date_2 AND date_2 + interval '1 month' = date_3 THEN 'yes'
	   Else 'no' END as yes_no
FROM level4
WHERE date_3 is not null)
SELECT *
FROM level5
WHERE yes_no = 'yes'

-- рішення цієї ж задачі від чатіка(еталон)

WITH m AS (
    SELECT DISTINCT
           customer_id,
           date_trunc('month', order_date)::date AS m
    FROM orders
),
grp AS (
    SELECT customer_id,
           m,
           (EXTRACT(YEAR FROM m) * 12 + EXTRACT(MONTH FROM m)
            - ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY m)) AS g
    FROM m
)
SELECT customer_id,
       MIN(m) AS start_month,
       MAX(m) AS end_month,
       COUNT(*) AS months_in_row
FROM grp
GROUP BY customer_id, g
HAVING COUNT(*) >= 3
ORDER BY customer_id;

-- 167. “Клієнти, які перестали купувати” (Churn Detection)

WITH level1 as(SELECT customer_id
       ,COUNT(*) as count_order
       ,MAX(order_date) as max_date_customer
	   ,(SELECT MAX(order_date) FROM orders) as total_max_date
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id),
level2 as(SELECT *
	   ,case when max_date_customer <= total_max_date - INTERVAL '90 days' THEN 'klient_vidpav'
	   ELSE 'klient_kupuye_dali' END as gradation
FROm level1)
SELECT *  
FROm level2
WHERE count_order >= 2 AND gradation = 'klient_vidpav'

-- 168. Потрібно знайти клієнтів, у яких варіація (стандартне відхилення) між сумами їхніх замовлень:
-- менше 10% від їхнього середнього чека, і мають мінімум 4 замовлення. Тобто це “стабільні” покупці.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as revenue_per_order
	   ,COUNT(*) OVER(partition by customer_id) as count_orders
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(AVG(revenue_per_order)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(revenue_per_order)::numeric,2) as stddev_chek
FROM level1
WHERE count_orders >= 4
GROUP BY customer_id),
level3 as(SELECT *
       ,ROUND((stddev_chek / avg_chek),2) as instability_ratio
FROm level2)
SELECT *
FROm level3
where instability_ratio < 0.1

-- 169. “Клієнти зі зростаючим трендом середнього чека”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as revenue_per_order
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id, order_date),
level2 as(SELECT *
       ,LAG(revenue_per_order) OVER(partition by customer_id order by order_date) as prev_revenue_per_order
FROm level1),
level3 as (SELECT *
       ,case when revenue_per_order > prev_revenue_per_order THEN 1 ELSE 0 END as flag_revenue
FROM level2
where prev_revenue_per_order is not null),
level4 as(SELECT *
       ,ROW_NUMBER() OVER (PARTITION BY customer_id order by order_date)
	   - ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY order_date, flag_revenue) as grp
FROM level3),
level5 as(SELECT customer_id
       ,SUM(flag_revenue) as sum_trend  
FROm level4
GROUP BY customer_id,grp)
SELECT *
FROM level5
WHERE sum_trend >= 2

Спробувати завтра вирішити цю задачу простішим способом
