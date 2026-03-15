-- 744. «Клієнт із прихованим центром ваги»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by rn)::numeric,0) as median_rn
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 12),
level4 as(SELECT *
       ,MAX(case when rn = median_rn THEN sum_chek END) OVER (partition by customer_id) as chek_median_rn
FROM level3),
level5 as(SELECT *
       ,NTILE(2) OVER (partition by customer_id order by sum_chek DESC) as ntile_chek
FROM level4),
level6 as(SELECT *
       ,MAX(sum_chek) FILTER (WHERE ntile_chek = 2) OVER (partition by customer_id) as max_chek_ntile_2
	   ,MIN(sum_chek) FILTER (WHERE ntile_chek = 2) OVER (partition by customer_id) as min_chek_ntile_2
FROM level5),
level7 as(SELECT DISTINCT customer_id
       ,count_order
	   ,median_rn
	   ,chek_median_rn
	   ,max_chek_ntile_2
	   ,min_chek_ntile_2
FROM level6)
SELECT *
FROM level7
WHERE chek_median_rn < max_chek_ntile_2 AND chek_median_rn > min_chek_ntile_2

-- 745. «Товар із фальшивою стабільністю»

WITH level1 as(SELECT product_id
       ,order_id
	   ,order_date
	   ,quantity
	   ,COUNT(product_id) OVER (partition by product_id) as count_product
	   ,COUNT(product_id) OVER (partition by product_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by product_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,case when rn <= middle_point THEn 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1),
level3 as(SELECT product_id
       ,SUM(quantity) FILTER (WHERE halfs = 'first') as sum_quantity_first
	   ,sum(quantity) FILTER (WHERE halfs = 'second') as sum_quantity_second
FROM level2
GROUP By product_id)
SELECT *
FROM level3
WHERE sum_quantity_first = sum_quantity_second

-- 746. «Товар із прихованою еластичністю попиту»

WITH level1 as(SELECT order_id
       ,order_date
	   ,product_id
	   ,quantity
	   ,(unit_price * (1-discount)) as net_price
	   ,COUNT(product_id) OVER (partition by product_id) as count_product
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
FROM level1
WHERE count_product >= 30),
level3 as(SELECT product_id
       ,ROUND(corr(quantity, net_price)::numeric,4) as corr_quantity_net_price
FROM level2
GROUP By product_id)
SELECT *
FROm level3
WHERE corr_quantity_net_price <= -0.6

-- 747. «Клієнт із ефектом кумулятивного зсуву центру»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_quantity) OVER (partition by customer_id order by order_date) as cumm_quantity
FROM level1),
level3 as(SELECT *
       ,ROUND(STDDEV(cumm_quantity) OVER (partition by customer_id)::numeric,4) as stddev_cumm_quantity
FROM level2),
level4 as(SELECT DISTINCT customer_id
       ,stddev_cumm_quantity
FROm level3),
level5 as(SELECT *
       ,ntile(10) OVER (order by stddev_cumm_quantity DESC) as ntile_10
FROm level4
WHERE stddev_cumm_quantity is not null)
SELECT *
FROm level5
WHERE ntile_10 = 1

-- 748. «Клієнт із прихованою точкою перелому»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
fROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_quantity) OVER (partition by customer_id order by order_date) as cumm_quantity
	   ,SUM(sum_quantity) OVER (partition by customer_id) as total_quantity
FROM level1),
level3 as(SELECT *
       ,ROUND((cumm_quantity::numeric / total_quantity::numeric),4) as ratio_quantity
FROM level2),
level4 as(SELECT *
	   ,MIN(case when ratio_quantity >= 0.5 THEN ratio_quantity END) OVER (partition by customer_id) as first_order_high_50_perc
FROM level3),
level5 as(SELECT *
       ,ROUND(STDDEV(sum_quantity) OVER (partition by customer_id)::numeric,4) as stddev_quantity
FROm level4
WHERE ratio_quantity = first_order_high_50_perc OR ratio_quantity < 0.5),
level6 as(SELECT DISTINCT customer_id
       ,stddev_quantity
FROm level5
WHERE stddev_quantity is not null),
level7 as(SELECT *
       ,NTILE(10) OVER (order by stddev_quantity DESC) as ntile_quantity
FROm level6)
SELECT *
FROm level7
WHERE ntile_quantity = 1

-- 749. «Клієнт із ефектом латентного прискорення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
FROM orders),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1
WHERE prev_date is not null),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by interval) as median_interval
FROm level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(STDDEV(interval) OVER (partition by customer_id)::numeric,4) as stddev_interval
FROM level2
JOIN level3 USING (customer_id)),
level5 as(SELECT DISTINCT customer_id
       ,median_interval
	   ,stddev_interval
FROM level4
WHERE stddev_interval is not null),
level6 as(SELECT *
       ,ntile(10) OVER (order by stddev_interval DESC) as ntile_stddev
FROM level5)
SELECT *
FROM level6
WHERE ntile_stddev = 1 AND median_interval < 30

-- 750.«Клієнт із ефектом концентраційного зсуву»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,SUM(quantity) OVER (partition by customer_id, order_id) as quantity_per_order
FROM level1),
level3 as(SELECT *
       ,ROUND((quantity::numeric / quantity_per_order::numeric),4) as ratio
FROM level2),
level4 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id, order_id order by ratio desc) as rn
FROM level3),
level5 as(SELECT *
       ,ROUND(STDDEV(ratio) OVER (partition by customer_id)::numeric,4) as stddev_ratio
FROM level4
WHERE rn = 1),
level6 as(SELECT DISTINCT customer_id
       ,stddev_ratio
FROM level5
WHERE stddev_ratio is not null),
level7 as(SELECT *
       ,ntile(10) OVER (order by stddev_ratio DESC) as ntile_stddev
FROM level6)
SELECT *
FROM level7
WHERE ntile_stddev = 1

-- 751. «Клієнт із ефектом повної осциляції»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(avg_price) OVER (partition by customer_id order by order_date) as next_price
FROM level1),
level3 as(SELECT *
       ,next_price - avg_price as delta_price
FROm level2
WHERE next_price is not null),
level4 as(SELECT *
       ,case when delta_price > 0 THEN 'delta_plus'
	   when delta_price < 0 THEN 'delta_minus'
	   when delta_price = 0 THEN 'equal_delta'
	   END as gradation
FROM level3),
level5 as(SELECT *
       ,LEAD(gradation) OVER (partition by customer_id order by order_date) as next_gradation
FROM level4),
level6 as(SELECT *
       ,case when (gradation = 'delta_plus' AND next_gradation = 'delta_minus') OR (gradation = 'delta_minus' AND next_gradation = 'delta_plus') THEN 1
	   ELSE 0 END as flag_gradation
FROM level5
WHERE next_gradation is not null),
level7 as(SELECT *
       ,SUM(flag_gradation) OVER (partition by customer_id) as sum_flag_gradation
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM level6)
SELECT *
FROm level7
WHERE count_order = sum_flag_gradation

