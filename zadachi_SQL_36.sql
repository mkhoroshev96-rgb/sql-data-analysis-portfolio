-- 222. Знайти всіх клієнтів, у яких немає жодного замовлення з кількістю товарів > 5.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date
ORDER BY customer_id, order_date),
level2 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as count_order
FROM level1),
level3 as(SELECT *
       ,case when sum_quantity <= 5 THEN 1 ELSE 0 END as flag_quantity 
FROM level2),
level4 as(SELECT *
       ,SUM(flag_quantity) OVER (partition by customer_id) as sum_flag_quantity
FROM level3)
SELECT *
FROM level4
WHERE sum_flag_quantity = count_order

-- 223. Знайти клієнтів, у яких жодне замовлення не вибивається за межі ±20% 
-- від їхнього середнього “order_size”.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as order_size
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id,order_date
ORDER BY customer_id,order_date),
level2 as(SELECT *
       ,ROUND(AVG(order_size) OVER (partition by customer_id)::numeric,2) as avg_order_size
FROM level1),
level3 as(SELECT *
       ,ROUND((order_size / avg_order_size),2) as ratio
FROM level2),
level4 as(SELECT *
       ,case when ratio >= 0.8 AND ratio <= 1.2 THEN 1 ELSE 0 END as flag_ratio
	   ,COUNT(*) OVER (partition by customer_id) as count_orders
FROM level3),
level5 as(SELECT *
       ,SUM(flag_ratio) OVER (partition by customer_id) as sum_flag_ratio
FROM level4)
SELECT *
FROM level5
WHERE count_orders = sum_flag_ratio

-- 224. Знайти клієнтів, у яких:
-- Середній чек у першій половині їхніх замовлень відрізняється від 
-- середнього чека у другій половині не більше ніж на 10%.
-- Кількість замовлень ≥ 4 (бо половини мають сенс).

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id, order_date),
level2 aS(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as count_order
	   ,ROW_number() OVER (partition by customer_id order by order_date) as rn
	   ,COUNT(*) OVER (partition by customer_id) / 2 as middle_point
FROM level1),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level2
where count_order >= 4),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (where halfs = 'first_half')::numeric,2) as avg_chek_per_1_half
	   ,ROUND(AVG(sum_chek) FILTER (where halfs = 'second_half')::numeric,2) as avg_chek_per_2_half
FROM  level3
GROUP BY customer_id),
level5 as(SELECT *
       ,ROUND((avg_chek_per_1_half / avg_chek_per_2_half),2) as ratio
FROM level4),
level6 as(SELECT *
       ,case when ratio >= 0.9 AND ratio <= 1.1 THEN 'yes'
	   ELSE 'no' END as flag
FROm level5)
SELECT *
FROM level6
WHERE flag = 'yes'

-- 225. Знайти клієнтів, у яких:
-- Останні 3 замовлення мають середній чек менший щонайменше на 15%, 
-- ніж середній чек їхніх попередніх усіх замовлень.
-- У клієнта має бути мінімум 6 замовлень, щоб “останні 3” і “попередні” мали сенс.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity *(1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id,order_date),
level2 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as count_order
	   ,ROW_number() OVER (partition by customer_id order by order_date DESC) as rn
FROM level1),
level3 as(SELECT *
       ,case when rn <= 3 THEN 'last_order'
	   ELSE 'other' END as flag
FROM level2
WHERE count_order >= 6),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (where flag = 'last_order')::numeric,2) as avg_chek_last_order
	   ,ROUND(AVG(sum_chek) FILTER (where flag = 'other')::numeric,2) as avg_chek_other
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
       ,ROUND((avg_chek_other / avg_chek_last_order),2) as ratio
FROM level4),
level6 as(SELECT *
       ,case when ratio >= 1.15 THEN 'yes'
	   ELSE 'no' END as flag_yes_no
FROm level5)
SELECT *
FROM level6
WHERE flag_yes_no = 'yes'

-- 226. Знайти клієнтів, у яких:
-- Стандартне відхилення їхніх чеків (sum_chek per order)
-- перевищує 40% від середнього чека.
-- Формула:stddev(sum_chek) / avg(sum_chek) >= 0.40
-- Клієнт має мінімум 5 замовлень (інакше stddev малоінформативне).

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as count_order
FROM level1),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek)::numeric,2) as std_dev_chek
FROM level2
WHERE count_order >= 5
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND((std_dev_chek / avg_chek),2) as ratio
FROM level3)
SELECT *
FROM level4
WHERE ratio >= 0.4

-- 227. Знайти клієнтів, у яких останні 3 замовлення відбуваються значно частіше, ніж попередні.

WITH level1 as(SELECT DISTINCT order_date
       ,customer_id
       ,order_id
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date DESC) as rn
	   ,COUNT(*) OVER (partition by customer_id) as count_order
FROM level1),
level3 as(SELECT *
       ,case when rn <= 3 THEN 'last_order'
	   ELSE 'other' END as flag_order
	   ,LAG(order_date) OVER (partition by customer_id order by order_date DESC) as prev_date
FROM level2
WHERE count_order >= 6),
level4 as(SELECT *
       ,prev_date - order_date as interval
FROM level3
WHERE prev_date is not null),
level5 as(SELECT customer_id
       ,ROUND(AVG(interval) FILTER (where flag_order = 'last_order')::numeric,2) as avg_interval_last_order
	   ,ROUND(AVG(interval) FILTER (where flag_order = 'other')::numeric,2) as avg_interval_other
FROM level4
GROUP BY customer_id),
level6 as(SELECT *
       ,ROUND((avg_interval_other / avg_interval_last_order),2) as ratio
FROM level5)
SELECT *
FROM level6
WHERE ratio >= 2

-- 228. Знайти клієнтів, у яких:кількість замовлень ≥ 5
-- максимальний чек замовлення ≥ 3 × медіанного чека цього клієнта

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as order_count
FROM level1),
level3 as(SELECT customer_id
	   ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
	   ,MAX(sum_chek) as max_chek
FROM level2
WHERE order_count >= 5
GROUP BY customer_id)
SELECT *
FROM level3
WHERE max_chek >= 3 * median_chek

-- 229. Знайти клієнтів, у яких:кількість замовлень ≥ 6
-- мінімальний чек замовлення ≤ 40% від середнього чека клієнта
-- максимальний чек замовлення ≥ 160% від середнього чека клієнта
-- Тобто клієнт має одночасно дуже дешеві і дуже дорогі замовлення відносно свого середнього.

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as count_order
FROM level1),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,MAX(sum_chek) as max_chek
	   ,MIN(sum_chek) as min_chek
FROM level2
WHERE count_order >= 6
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND((max_chek / avg_chek),2) as max_ratio
	   ,ROUND((min_chek / avg_chek),2) as min_ratio
FROM level3)
SELECT *
FROM level4
WHERE max_ratio >= 1.6 AND min_ratio <= 0.4