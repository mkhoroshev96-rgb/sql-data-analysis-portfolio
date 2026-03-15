-- 261. «Клієнти з ефектом повтору»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id,order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROM level1
WHERE count_order >= 3),
level3 as(SELECT *
       ,case when sum_quantity = prev_quantity THEN 'yes'
	   ELSE 'no' END AS flag
FROM level2)
SELECT *
FROM level3
WHERE flag = 'yes'

-- 262. «Клієнти з різким стрибком кошика»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROM level1
WHERE count_order >= 4),
level3 as(SELECT *
       ,ROUND((sum_quantity::numeric / prev_quantity::numeric)::numeric,2) as ratio
FROM level2)
SELECT *
FROM level3
WHERE ratio >= 2

-- 263. «Клієнти з просіданням кошика»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,DENSE_RANK() OVER (partition by customer_id order by order_date DESC) as rank_invert
FROM level1
WHERE count_order >= 3),
level3 as(SELECT *
       ,case when rank_invert = 1 THEN 'last_order'
	   ELSE 'other' END as flag_order
FROm level2),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE flag_order = 'last_order')::numeric,2) as quantity_last_order
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE flag_order = 'other')::numeric,2) as quantity_other_orders
FROM level3
GROUP BY customer_id)
SELECT *
FROm level4
WHERE quantity_other_orders > quantity_last_order

-- 264. «Клієнти з нестабільною серединою»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,FIRST_VALUE(order_date) OVER (partition by customer_id order by order_date) as first_date
	   ,FIRST_VALUE(order_date) OVER (partition by customer_id order by order_date DESC) as last_date
FROm level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,case when order_date = first_date THEN 'fir_date'
	   when order_date = last_date THEN 'las_date'
	   ELSE 'other' END as flag_date
FROm level2),
level4 as(SELECT *
       ,MAX(sum_quantity) OVER (partition by customer_id) as max_quantity
	   ,MIN(sum_quantity) OVER (partition by customer_id) as min_quantity
FROm level3
WHERE flag_date = 'other')
SELECT *
FROM level4
WHERE max_quantity >= min_quantity * 2

-- 265. «Клієнти з “повтором складу”»

WITH level1 as(SELECT customer_id
       ,order_id
       ,order_date
	   ,product_id
	   ,ROW_NUMBER() OVER (partition by customer_id,order_id order by product_id) as rn
	   ,COUNT(*) OVER (partition by customer_id, order_id) as count_order
FROM orders
JOIn order_details USING(order_id)),
level2 as(SELECT *
       ,DENSE_rank() OVER (partition by customer_id order by order_date) as rn_set
FROM level1)
SELECT *
FROM level2 t1
JOIN level2 t2 On t1.customer_id = t2.customer_id 
AND t1.order_date <> t2.order_date AND t1.order_id < t2.order_id
AND t1.rn = t2.rn
AND t1.product_id = t2.product_id
AND t1.count_order = t2.count_order

-- 266. “Клієнти з нестабільним кошиком”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id,order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
	   ,MAX(sum_quantity) OVER (partition by customer_id) as max_quantity
FROm level1
WHERE count_order >= 3)
SELECT DISTINCT customer_id
       ,avg_quantity
	   ,max_quantity
FROm level2
WHERE max_quantity > avg_quantity * 2

-- 267. “Клієнти з різкою зміною щільності замовлень”

WITh level1 as(SELECT DISTINCT order_date
       ,customer_id
	   ,order_id
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,COUNT(order_id) OVER(partition by customer_id) as count_order
	   ,COUNT(order_id) OVER(partition by customer_id) / 2 as middle_point
FROM level1),
level3 as(SELECT *
		,order_date - prev_date as interval
		,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
FROM level2
WHERE count_order >= 5 AND prev_date is not null),
level4 as (SELECT *
       ,case when rn <= middle_point THEN 'first_half'
		when rn > middle_point THEN 'second_half'
		END as halfs 
FROM level3),
level5 as(SELECT customer_id
       ,ROUND(AVG(interval) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_int_fir_half
	   ,ROUND(AVG(interval) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_int_sec_half
FROM level4
GROUP BY customer_id),
level6 as(SELECT *
       ,ROUND((avg_int_fir_half::numeric / avg_int_sec_half::numeric),2) as ratio
FROM level5)
SELECT *
FROm level6
WHERE ratio >= 1.5



