-- 275. «Клієнти з нерівномірною структурою замовлень»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity)::numeric,2) as avg_quantity
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level1
WHERE count_order >= 5
GROUP By customer_id)
SELECT *
FROM level2
WHERE avg_quantity > median_quantity

-- 276. «Клієнти з контрастними замовленнями»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_quantity) OVER (partition by customer_id) as max_quantity
	   ,MIN(sum_quantity) OVER (partition by customer_id) as min_quantity
	   ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
FROM level1
WHERE count_order >= 5),
level3 as(SELECT DISTINCT customer_id
       ,max_quantity - min_quantity as diff
	   ,avg_quantity
FROM level2)
SELECT *
FROm level3
WHERE diff > avg_quantity

-- 277. «Клієнти з полярною знижковою поведінкою»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,AVG(discount) as avg_discount
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT customer_id
       ,ROUND((AVG(avg_discount)*100)::numeric,2) as avg_discount
	   ,ROUND((percentile_cont(0.5) WITHIN GROUP (order by avg_discount) * 100)::numeric,2) as median_discount
FROM level1
WHERE count_order >= 5
GROUP BY customer_id)
SELECT *
FROM level2
WHERE avg_discount > median_discount

-- 278. «Клієнти з нестабільною географією доставки»

WITH level1 as(SELECT customer_id
       ,ship_country
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id,ship_country, order_id)
SELECT customer_id
       ,COUNT(DISTINCT ship_country)
FROM level1
WHERE count_order >= 5
GROUP By customer_id

-- 279. “Клієнти з «перекосом постачальника»”

WITh level1 as(SELECT customer_id
       ,supplier_id
       ,COUNT(DISTINCT product_id) as count_unik_product
FROM orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
JOIN suppliers USING(supplier_id)
GROUP BY customer_id,supplier_id
ORDER BY customer_id),
level2 as(SELECT *
       ,SUM(count_unik_product) OVER (partition by customer_id) as total_count
FROm level1),
level3 as(SELECT *
       ,ROUND((count_unik_product::numeric / total_count::numeric),2) as ratio
FROM level2),
level4 as(SELECT *
FROM level3
WHERE ratio >= 0.6),
level5 as(SELECT customer_id
       ,supplier_id
	   ,SUM(quantity) as sum_quantity
FROM orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
JOIN suppliers USING(supplier_id)
GROUP BY customer_id,supplier_id
ORDER BY customer_id),
level6 as(SELECT *
       ,SUM(sum_quantity) OVER (partition by customer_id) as total_quantity
FROM level5),
level7 as(SELECT *
       ,ROUND((sum_quantity::numeric / total_quantity::numeric * 100),2) as ratio_quantity
FROM level6),
level8 as(SELECT *
FROM level4
JOIN level7 USING(customer_id, supplier_id)
WHERE ratio_quantity <= 35),
level9 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM orders
GROUP By customer_id),
level10 as(SELECT *
FROm level8
JOIN level9 USING(customer_id))
SELECT *
FROm level10
WHERE count_order >= 6

-- 280. «Клієнти з ілюзією зростання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when rn <= 3 THEN 'first_3_order' ELSE 'other' END as rn_first
	   ,case when rn_invert <= 3 THEN 'second_3_order' ELSE 'other' END as rn_second
FROM level2),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE rn_first = 'first_3_order')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE rn_second = 'second_3_order')::numeric,2) as avg_quantity_second
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) FILTER (WHERE rn_first = 'first_3_order') as median_first
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) FILTER (WHERE rn_second = 'second_3_order') as median_second
FROM level3
GROUP BY customer_id)
SELECT *
FROM level4
WHERE avg_quantity_second > avg_quantity_first AND median_second <= median_first

-- 281. «Клієнти з ілюзією лояльності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ship_via
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id, order_date, ship_via),
level2 as(SELECT *
       ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when rn <= 3 THEN 'first_3' ELSE 'other' END as rn_first
	   ,case when rn_invert <= 3 THEN 'last_3' ELSE 'other' END as rn_last
FROM level2),
level4 as(SELECT customer_id
       ,ship_via
	   ,COUNT(ship_via) FILTER (WHERE rn_first = 'first_3') as count_first
	   ,COUNT(ship_via) FILTER (WHERE rn_last = 'last_3') as count_second 
FROm level3
GROUP BY customer_id, ship_via),
level5 as(SELECT customer_id
       ,COUNT(DISTINCT ship_via) FILTER (WHERE  rn_first = 'first_3') as count_dist_first
	   ,COUNT(DISTINCT ship_via) FILTER (WHERE rn_last = 'last_3') as count_dist_second
FROM level3
GROUP BY customer_id),
level6 as(SELECT *
FROM level4
JOIN level5 USING(customer_id)),
level7 as(SELECT * 
       ,ROUND((count_first::numeric / 3),2) as ratio_first
	   ,ROUND((count_second::numeric / 3),2) as ratio_second
FROM level6)
SELECT *
FROM level7
where ratio_second > ratio_first AND count_dist_first = count_dist_second

-- 282. «Клієнти з нетиповим замовленням»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
	   ,ROUND(STDDEV(sum_quantity) OVER (partition by customer_id)::numeric,2) as std_dev_quantity
FROm level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,case when sum_quantity > avg_quantity + std_dev_quantity THEN 'yes'
	   ELSE 'no' END as flag
FROM level2)
SELECT *
FROm level3
WHERE flag = 'yes'

-- 283. «Клієнти з нестабільною кількістю позицій»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,COUNT(order_id) as count_order_id
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT customer_id
       ,ROUND(AVG(count_order_id)::numeric,2) as avg_count_order_id
	   ,percentile_cont(0.5) WITHIN GROUP (order by count_order_id) as median_order_id
FROm level1
GROUP BY customer_id)
SELECT *
FROM level2
WHERE median_order_id > avg_count_order_id