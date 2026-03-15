-- 284. «Клієнти з “нерівною вагою” замовлень»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
Join order_details USING(order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,SUM(sum_quantity) OVER (partition by customer_id) as total_quantity_per_customer
FROM level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,ROUND((sum_quantity::numeric / total_quantity_per_customer::numeric * 100),2) as ratio
FROM level2)
SELECT *
FROm level3
WHERE ratio > 50

-- 285. «Клієнти з різкою зміною розміру замовлень»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
	   ,COUNT(order_id) OVER (partition by customer_id) /2 as middle_point
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when rn <= 3 THEN 'first_3' ELSE 'other' END as flag_first_3
	   ,case when rn_invert <= 3 THEN 'last_3' ELSE 'other' END as flag_last_3
FROM level2),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE flag_first_3 = 'first_3')::numeric,2) as avg_first_3
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE flag_last_3 = 'last_3')::numeric,2) as avg_last_3
	   ,SUM(sum_quantity) FILTER (WHERE halfs = 'first_half') as total_quantity_first_half
	   ,SUM(sum_quantity) FILTER (WHERE halfs = 'second_half') as total_quantity_second_half
FROM level3
GROUP By customer_id)
SELECT *
FROM level4
WHERE avg_first_3 > avg_last_3 AND total_quantity_second_half > total_quantity_first_half

-- 286. «Клієнти з ефектом стиснутого кошика»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity)::numeric,2) as avg_quantity
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
FROm level1
WHERE count_order >= 5
GROUP By customer_id)
SELECT *
FROm level2
WHERE median_quantity > avg_quantity AND median_chek > avg_chek

-- 287. «Клієнти з ефектом хибного зростання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= 3 THEN 'first_3' ELSE 'other' END as flag_first
	   ,case when rn_invert <= 3 THEN 'last_3' ELSE 'other' END as flag_last
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE flag_first = 'first_3')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE flag_last = 'last_3')::numeric,2) as avg_chek_second
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE flag_first = 'first_3')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE flag_last = 'last_3')::numeric,2) as avg_quantity_second
FROm level2
GROUP By customer_id)
SELECT *
FROM level3
WHERE avg_chek_second > avg_chek_first AND avg_quantity_first > avg_quantity_second

-- 288. «Клієнти з ефектом стабільної деградації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id,order_id,order_date),
level2 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek 
FROM level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half' 
	   END as halfs
       ,COUNT(order_id) OVER (partition by customer_id) as real_count_order
FROM level2
WHERE next_chek is not null),
level4 as(SELECT *
       ,case when sum_chek > next_chek THEN 1 ELSE 0 END as flag_chek
FROM level3),
level5 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level4),
level6 as(SELECT *
       ,case when sum_flag_chek = real_count_order OR sum_flag_chek = real_count_order - 1 THEN 'yes'
	   ELSE 'no' END as gradation
FROM level5),
level7 as(SELECT *
       ,SUM(sum_quantity) FILTER (WHERE halfs = 'first_half') OVER (partition by customer_id) as total_quantity_first
	   ,SUM(sum_quantity) FILTER (WHERE halfs = 'second_half') OVER (partition by customer_id) as total_quantity_second
FROM level6
WHERE gradation = 'yes')
SELECT *
FROM level7
WHERE total_quantity_first < total_quantity_second

-- 289. “Клієнти з ілюзією лояльності”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
FROM orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
	   ,count_order - 1 as real_count_order
	   ,(count_order - 1) / 2 as middle_point
FROM level1
WHERE count_order >= 8),
level3 as(SELECT *
FROM level2
WHERE interval is not null),
level4 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by interval) as median_interval
FROM level3
GROUP By customer_id),
level5 as(SELECT *
       ,case when interval > median_interval THEN 1 ELSE 0 END as flag_interval
	   ,case when rn <= middle_point THEN 'first_half'
	   when rn> middle_point THEN 'second_half'
	   END as halfs
FROm level3
JOIN level4 USING(customer_id)),
level6 as(SELECT *
       ,SUM(flag_interval) OVER (partition by customer_id) as sum_flag_interval
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first_half') OVER (partition by customer_id)::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second_half') OVER (partition by customer_id)::numeric,2) as avg_chek_second
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'first_half') OVER (partition by customer_id) as total_chek_first
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'second_half') OVER (partition by customer_id) as total_chek_second
FROM level5)
SELECT *
FROM level6
WHERE avg_chek_second > avg_chek_first 
AND total_chek_first > total_chek_second 
AND sum_flag_interval <= 1

-- 290. “Клієнти з ефектом помилкового відновлення”**

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
FROM orders
JOIn order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,MAX(interval) OVER (partition by customer_id) as max_interval
FROm level2),
level4 as(SELECT *
       ,MAX(case when interval = max_interval THEN order_date END) OVER (partition by customer_id) as date_in_max_interval
FROM level3),
level5 as(SELECT *
       ,case when order_date < date_in_max_interval THEN '1_before'
	   when order_date > date_in_max_interval THEN '2_after'
	   else 'pause'
	   END as flag_date
FROM level4),
level6 as(SELECT *
FROM level5
WHERE flag_date IN ('1_before','2_after') AND prev_date is not null),
level7 as(SELECT *
       ,COUNT(flag_date) FILTER (where flag_date = '1_before') OVER (partition by customer_id) as count_before
	   ,COUNT(flag_date) FILTER (where flag_date = '2_after') OVER (partition by customer_id) as count_after
FROM level6),
level8 as(SELECT *
       ,ROW_NUMBER()  OVER (partition by customer_id,flag_date order by order_date DESC) as rn_before
	   ,ROW_NUMBER()  OVER (partition by customer_id,flag_date order by order_date ASC) as rn_after
FROM level7
WHERE count_before >= 2 AND count_after >= 2),
level9 as(SELECT *
FROM level8
WHERE (flag_date = '1_before' AND rn_before <= 2) 
OR (flag_date = '2_after' AND rn_after <= 2)),
level10 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE flag_date = '1_before')::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE flag_date = '2_after')::numeric,2) as avg_chek_after
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE flag_date = '1_before')::numeric,2) as avg_quantity_before
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE flag_date = '2_after')::numeric,2) as avg_quantity_after
	   ,SUM(sum_chek) FILTER (WHERE flag_date = '1_before') as total_chek_before
	   ,SUM(sum_chek) FILTER (WHERE flag_date = '2_after') as totaL_chek_after
FROm level9
WHERE rn_before <= 2
GROUP BY customer_id)
SELECT *
FROM level10
WHERE avg_chek_after > avg_chek_before 
AND avg_quantity_before > avg_quantity_after
AND total_chek_before > totaL_chek_after
