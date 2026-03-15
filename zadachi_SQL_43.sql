-- 268. “Клієнти з розмитою спеціалізацією”

WITH level1 as(SELECT customer_id
	   ,category_id
	   ,SUm(quantity) as sum_quantity
FROm orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
JOIN categories USING(category_id)
GROUP BY customer_id, category_id
ORDER BY customer_id, category_id),
level2 as(SELECT *
       ,SUM(sum_quantity) OVER (partition by customer_id) as total_sum_per_customer
FROm level1),
level3 as(SELECT *
       ,ROUND((sum_quantity::numeric / total_sum_per_customer::numeric * 100),2) as ratio 
FROM level2),
level4 as(SELECT *
       ,CASE WHEN ratio >= 40 THEN 1
	   ELSE 0 END as flag
FROm level3),
level5 as(SELECT *
       ,SUM(flag) OVER (partition by customer_id) as sum_flag
FROM level4),
level6 as(SELECT *
FROM level5
WHERE sum_flag = 0),
level7 as(SELECT customer_id
       ,COUNT(DISTINCT order_id) as count_order
FROM orders
GROUP BY customer_id),
level8 as(SELECT *
FROM level6
JOIN level7 USING(customer_id))
SELECT *
FROM level8
WHERE count_order >= 4

-- 269. «Клієнти з нестабільним розміром кошика»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,MAX(sum_quantity) OVER (partition by customer_id) as max_quantity
	   ,MIN(sum_quantity) OVER (partition by customer_id) as min_quantity
FROM level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,ROUND((max_quantity::numeric / min_quantity::numeric),2) as ratio 
FROM level2)
SELECT *
FROM level3
WHERE ratio >= 2

-- 270. «Клієнти з ефектом різкого перелому»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id,order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
       ,LEAD(sum_quantity) OVER (partition by customer_id order by order_date) as next_quantity
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,LAG(prev_quantity) OVER (partition by customer_id order by order_date) as prev_2_quantity
	   ,LEAD(next_quantity) OVER (partition by customer_id order by order_date) as next_2_quantity
FROm level2),
level4 as(SELECT *
       ,(prev_quantity + prev_2_quantity)/2 as avg_prev_2
	   ,(next_quantity + next_2_quantity)/2 as avg_next_2
FROM level3
WHERE prev_2_quantity is not null AND next_2_quantity is not null),
level5 as(SELECT *
       ,case when avg_next_2 < avg_prev_2 THEn 'yes'
	   ELSE 'no' END as flag
FROM level4)
SELECT *
FROM level5
where flag = 'yes'

-- 271. «Клієнти з нерівномірним темпом замовлень»

WITH level1 as(SELECT DISTINCT order_id
       ,customer_id
	   ,order_date
FROM orders
JOIn order_details USING(order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM level1),
level3 as(SELECT *
       ,order_date - prev_date as interval
FROM level2
WHERE count_order >= 5),
level4 as(SELECT customer_id
       ,percentile_cont(0.5) within group (order by interval) as median_interval
FROM level3
WHERE interval is not null
GROUP BY customer_id),
level5 as(SELECT *
       ,MAX(interval) OVER (partition by customer_id) as max_interval
FROM level3
JOIN level4 USING(customer_id)
WHERE interval is not null),
level6 as(SELECT *
       ,ROUND((max_interval::numeric / median_interval::numeric),2) as ratio
FROm level5)
SELECT *
FROm level6
WHERE ratio >= 3

-- 272. «Клієнти з різкою зміною середнього розміру замовлення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id,order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   WHEN rn > middle_point THEN 'second_half'
	   END as halfs
FROM level1),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_qnt_fir_half
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_qnt_sec_half
FROm level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND((avg_qnt_fir_half / avg_qnt_sec_half),2) as ratio
FROm level3)
SELECT *
FROM level4
WHERE ratio >= 1.43

-- 273. «Клієнти з аномально “тихими” замовленнями»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,MIN(sum_quantity) OVER (partition by customer_id) as min_quantity
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level1
GROUP BY customer_id),
level4 as(SELECT *
FROm level2
JOIN level3 USING(customer_id)),
level5 as(SELECT *
       ,ROUND((min_quantity::numeric / median_quantity::numeric),2) as ratio 
FROm level4)
SELECT *
FROM level5
WHERE ratio <= 0.6

-- 274. «Клієнти з одним “аномальним” замовленням»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
	   ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
FROM level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,ROUND((sum_quantity::numeric / avg_quantity::numeric),2) as ratio
FROM level2),
level4 as(SELECT *
       ,COUNT(ratio) OVER (partition by customer_id) as count_ratio
FROM level3
WHERE ratio >= 2)
SELECT *
FROM level4
WHERE count_ratio = 1

