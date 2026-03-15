-- 455. «Клієнт із ефектом “стрибка інерції”»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(avg_price) OVER (partition by customer_id order by order_date) as prev_price
	   ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
FROM level2
WHERE prev_price is not null AND prev_quantity is not null)
SELECT *
FROM level3
WHERE avg_price >= 2 * prev_price AND sum_quantity <= prev_quantity

-- 456. «Замовлення з незмінною вагою, але зміненою пам’яттю»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELEct *
       ,SUM(sum_quantity) OVER (partition by customer_id order by order_date) as cumm_sum_quantity
	   ,SUM(sum_quantity) OVER (partition by customer_id) as total_quantity
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,order_id
	   ,COUNT(DISTINCT product_id) as count_unik_prod
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id),
level4 as(SELECT *
       ,SUM(count_unik_prod) OVER (partition by customer_id order by order_date) as cumm_count_unik_prod
	   ,SUM(count_unik_prod) OVER (partition by customer_id) as total_count_unik_prod
FROM level2
JOIN level3 USING (customer_id, order_id)),
level5 as(SELECT *
       ,ROUND((sum_quantity::numeric / count_unik_prod::numeric),2) as quantity_per_product
FROM level4),
level6 as(SELECT *
       ,SUM(quantity_per_product) OVER (partition by customer_id order by order_date) as cumm_sum_quantity_per_product
	   ,SUM(quantity_per_product) OVER (partition by customer_id) as total_quantity_per_product
FROM level5),
level7 as(SELECT *
       ,ROUND((cumm_sum_quantity::numeric / total_quantity::numeric),2) as diff_quantity
	   ,ROUND((cumm_count_unik_prod::numeric / total_count_unik_prod::numeric),2) as diff_count_unik_prod
	   ,ROUND((cumm_sum_quantity_per_product / total_quantity_per_product),2) as diff_quantity_per_product
FROM level6),
level8 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,diff_quantity
	   ,diff_count_unik_prod
	   ,diff_quantity_per_product
FROM level7),
level9 as(SELECT *
       ,LAG(diff_quantity) OVER (partition by customer_id order by order_date) as prev_diff_quantity
	   ,LAG(diff_count_unik_prod) OVER (partition by customer_id order by order_date) as prev_diff_count_unik_prod
	   ,LAG(diff_quantity_per_product) OVER (partition by customer_id order by order_date) as prev_diff_quantity_per_product
FROM level8),
level10 as(SELECT *
       ,ROUND((diff_quantity / prev_diff_quantity),2) as ratio_quantity
	   ,ROUND((diff_count_unik_prod / prev_diff_count_unik_prod),2) as ratio_count_unik_prod
	   ,ROUND((diff_quantity_per_product / prev_diff_quantity_per_product),2) as ratio_diff_quantity_per_product
FROM level9)
SELECT *
FROM level10
WHERE ratio_quantity is not null 
AND ratio_count_unik_prod is not null 
and ratio_diff_quantity_per_product is not null

-- 457. «Замовлення з ефектом “невидимого видалення”»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,COUNT(distinct product_id) as count_unik
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
FROm level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
FROM orders
JOIN order_details USING (order_id)),
level4 as(SELECT *
       ,DENSE_RANK () OVER (partition by customer_id order by order_date) as rn
       ,LAG(order_id) OVER (partition by customer_id,product_id order by order_date) as prev_order
	   ,LEAD(order_id) OVER (partition by customer_id, product_id order by order_date) as next_order
FROM level2
JOIN level3 USING (customer_id, order_id,order_date)),
level5 as(SELECT *
FROM level4
WHERE prev_order is not null OR next_order is not null),
level6 as(SELECT *
       ,LAG(rn) OVER (partition by customer_id,product_id order by order_date) as prev_rn
FROM level5),
level7 as(SELECT *
       ,prev_rn + 2 as rn_plus_2
FROm level6
WHERE prev_rn is not null)
SELECT *
FROM level7
WHERE rn = rn_plus_2

-- 458. «Замовлення з ефектом зламаної пропорції»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND((sum_quantity::numeric / prev_quantity::numeric),2) as local_ratio
FROM level2),
level4 as(SELECT *
       ,LEAD(local_ratio) OVER (partition by customer_id order by order_date) as next_local_ratio
FROM level3),
level5 as(SELECT *
       ,case when local_ratio <= 1.05 AND local_ratio >= 0.95 THEN 'yes'
	   ELSE 'no' END as flag_local
	   ,case when next_local_ratio >= 1.5 OR next_local_ratio <= 0.5 THEN 'yes'
	   ELSE 'no' END as flag_next_local
FROM level4)
SELECT *
FROM level5
WHERE flag_local = 'yes' AND flag_next_local = 'yes'

-- 459. «Замовлення з ефектом “зламаної інерції другого порядку”»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,sum_quantity - prev_quantity as delta
FROM level2),
level4 as(SELECT *
       ,LAG(delta) OVER (partition by customer_id order by order_date) as prev_delta
FROM level3),
level5 as(SELECT *
       ,delta - prev_delta as accel
FROM level4),
level6 as(SELECT *
       ,case when delta Between -1 AND 1 THEN 'yes'
	   ELSE 'no' END as flag_delta
	   ,case when accel <= -20 OR accel >= 20 THEN 'yes'
	   ELSE 'no' END as flag_accel
FROM level5)
SELECT *
FROM level6
WHERE flag_delta = 'yes' AND flag_accel = 'yes'

-- 460. «Замовлення з ефектом стабільного центру»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,sum(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median
FROM level1
GROUP By customer_id),
level3 as(SELECT *
       ,sum_quantity - median as deviation
FROM level1
JOIN level2 USING (customer_id)),
level4 as(SELECT *
       ,LAG(deviation) OVER (partition by customer_id order by order_date) as prev_deviation
	   ,LEAD(deviation) OVER (partition by customer_id order by order_date) as next_deviation
FROm level3),
level5 as(SELeCT *
       ,case when deviation BETWEEN -1 AND 1 THEN 'yes'
	   ELSE 'no' END as flag_dev
	   ,case when (prev_deviation > 0 AND next_deviation > 0) OR (prev_deviation < 0 AND next_deviation < 0) THEN 'yes'
	   ELSE 'no' end as flag_prev_next
FROM level4
WHERE prev_deviation is not null AND next_deviation is not null)
SELECT *
FROM level5
WHERE flag_dev = 'yes' AND flag_prev_next = 'yes'