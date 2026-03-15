-- 308. «Клієнти з ефектом перекосу замовлень»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level2 as (SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,SUM(sum_quantity) OVER (partition by customer_id) as total_quantity
FROm level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,ROUND(((sum_chek::numeric / total_revenue::numeric)*100),2) as ratio_chek
	   ,ROUND(((sum_quantity::numeric / total_quantity::numeric)*100),2) as ratio_quantity
FROM level2)
SELECT *
FROM level3
WHERE ratio_chek >= 40 AND ratio_quantity <= 30

-- 309. «Клієнти з ефектом дорогого повернення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1
WHERE count_order >= 6 AND prev_date is not null),
level3 as(SELECT *
       ,MAX(interval) OVER (partition by customer_id) as max_interval
FROM level2),
level4 as(SELECT *
       ,MAX(case when max_interval = interval THen order_date END) OVER (partition by customer_id) as date_in_max_interval
FROM level3),
level5 as(SELECT *
       ,case when order_date < date_in_max_interval THEN '1_before_group'
	   when order_date > date_in_max_interval THEN '2_after_group'
	   when order_date = date_in_max_interval THEN 'pause' END as groups
FROM level4),
level6 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id, groups order by order_date) as rn
FROM level5
WHERE groups IN ('1_before_group','2_after_group')),
level7 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE groups = '1_before_group')::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE groups = '2_after_group' AND rn = 1)::numeric,2) as avg_chek_after
FROM level6
GROUP BY customer_id)
SELECT *
FROm level7
WHERE avg_chek_after > avg_chek_before

-- 310. «Клієнти з ілюзією зростання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as gradation
FROM level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'first_half')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'second_half')::numeric,2) as avg_chek_second
	   ,ROUND(SUM(sum_chek) FILTER (WHERE gradation = 'first_half')::numeric,2) as total_revenue_first
	   ,ROUND(SUM(sum_chek) FILTER (WHERE gradation = 'second_half')::numeric,2) as total_revenue_second
FROM level2
GROUP BY customer_id)
SELECT *
FROM level3
WHERE avg_chek_second > avg_chek_first AND total_revenue_second < total_revenue_first

-- 311. «Клієнти з ефектом дорогого шуму»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROM level1
WHERE count_order >= 7),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN group (order by sum_chek) as median_chek
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
FROM level2
JOIN level3 USING(customer_id)),
level5 as(SELECT *
       ,ROUND(((sum_chek::numeric / total_revenue::numeric)*100),2) as ratio_chek
FROM level4),
level6 as(SELECT *
       ,case when ratio_chek >= 35 THEN 1 ELSE 0 END as flag_ratio
FROM level5),
level7 as(SELECT *
       ,SUM(flag_ratio) OVER (partition by customer_id) as sum_flag_ratio
FROm level6)
SELECT *
FROM level7
WHERE median_chek < avg_chek AND sum_flag_ratio = 0

-- 312. «Клієнти з ілюзією стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROm level2
GROUP By customer_id,halfs),
level4 as(SELECT *
FROM level2
JOIN level3 USING(customer_id,halfs)),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_chek_second
	   ,AVG(median_quantity) FILTER (WHERE halfs = 'first_half') as median_quantity_first
	   ,AVG(median_quantity) FILTER (WHERE halfs = 'second_half') as median_quantity_second
FROM level4
GROUP BY customer_id),
level6 as(SELECT *
       ,ROUND(ABS((avg_chek_second::numeric - avg_chek_first::numeric) / (avg_chek_first::numeric) *100),2) as abs_ratio_chek
	   ,ROUND(ABS((median_quantity_second::numeric - median_quantity_first::numeric) / (median_quantity_first::numeric) *100),2) as abs_ratio_quantity 
FROm level5),
level7 as(SELECT *
       ,case when abs_ratio_quantity <= 10 THEN 'yes' ELSE 'no' END as flag_quantity
	   ,case when abs_ratio_chek >= 30 THEN 'yes' ELSE 'no' END as flag_chek
FROM level6)
SELECT *
FROM level7
WHERE flag_quantity = 'yes' AND flag_chek = 'yes' 

-- 313. «Клієнти, які стають “вигіднішими”, але гіршими»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price * (1-discount))::numeric,2) as avg_price
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as order_count
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level1
WHERE order_count >= 7),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_chek_second
	   ,ROUND(AVG(avg_price) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_price_first
	   ,ROUND(AVG(avg_price) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_price_second
FROM level2
GROUP BY customer_id)
SELECT *
FROM level3
WHERE avg_chek_second > avg_chek_first AND avg_price_second < avg_price_first

-- 314. «Клієнти з ефектом фальшивої лояльності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) /2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
	   ,order_date - prev_date as interval
FROM level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,ROUND(AVG(interval) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_interval_first
	   ,ROUND(AVG(interval) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_interval_second
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'first_half') as total_revenue_first
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'second_half') as total_revenue_second
FROM level2
GROUP BY customer_id)
SELECT *
FROM level3
WHERE avg_interval_first > avg_interval_second AND total_revenue_first > total_revenue_second
