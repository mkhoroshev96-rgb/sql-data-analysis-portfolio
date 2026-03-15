-- 398. «Клієнт, який не заробляє на знижках»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(AVG(discount)::numeric,4) as avg_discount
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek_real
	   ,ROUND(SUM(unit_price * quantity)::numeric,2) as sum_chek_no_disc
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details using(order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(avg_discount) OVER (partition by customer_id)::numeric,4) as avg_discount_customer
	   ,ROUND(AVG(avg_discount) OVER ()::numeric,4) as global_avg_discount
FROm level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,ROUND(AVG(sum_chek_real) OVER (partition by customer_id)::numeric,2) as avg_chek_real
	   ,ROUND(AVG(sum_chek_no_disc) OVER (partition by customer_id)::numeric,2) as avg_chek_no_disc
FROM level2
WHERE avg_discount_customer > global_avg_discount)
SELECT *
FROM level3
WHERE avg_chek_real < avg_chek_no_disc

-- 399. «Клієнт із ілюзією стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek_customer
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as std_dev_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND((std_dev_chek / avg_chek_customer)::numeric,2) as cv
FROM level2),
level4 as(SELECT *
       ,ROUND(AVG(cv) OVER ()::numeric,2) as global_avg_cv
FROM level3),
level5 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek_customer
FROM level4
GROUP By customer_id),
level6 as(SELECT *
       ,ROUND(ABS((avg_chek_customer - global_avg_chek) / global_avg_chek)::numeric,2) as ratio
FROm level4
JOIN level5 USING (customer_id))
SELECT *
FROM level6
WHERE ratio <= 0.1 AND cv > global_avg_cv 
AND median_chek_customer < avg_chek_customer

-- 400. «Клієнт, який вигідний тільки на папері»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek_customer
       ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > global_avg_chek THEN 1 ELSE 0 END as flag_chek
FROM level2
WHERE count_order >= 6 AND avg_chek_customer > global_avg_chek),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level3),
level5 as(SELECT *
       ,ROUND(((sum_flag_chek::numeric / count_order::numeric) * 100),2) as ratio_chek
FROM level4)
SELECT *
FROm level5
WHERE ratio_chek < 50

-- 401. «Клієнт без типового замовлення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id,order_id),
level2 as(SELECT *
       ,(SELECT percentile_cont(0.25) WITHIN GROUP (order by sum_chek) FROM level1) as percentile_25
	   ,(SELECT percentile_cont(0.75) WITHIN GROUP (order by sum_chek) FROM level1) as percentile_75
	   ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by sum_chek) FROM level1) as median_chek
FROM level1),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek_customer
FROM level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(ABS((median_chek_customer - median_chek) / median_chek)::numeric,2) as diff_chek
FROm level2
JOIN level3 USING (customer_id)),
level5 as(SELECT *
       ,case when sum_chek Between percentile_25 AND percentile_75 THEN 1 ELSE 0 END as flag_percentile
FROM level4
WHERE count_order >= 7 AND diff_chek <= 0.1),
level6 as(SELECT *
       ,SUM(flag_percentile) OVER (partition by customer_id) as sum_flag_percentile
FROM level5)
SELECT *
FROm level6
WHERE sum_flag_percentile = 0

-- 402. «Клієнт з нестабільною ефективністю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
	   ,COUNT(product_id) OVER (partition by order_id) as count_item
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,SUM(chek) OVER (partition by order_id) as sum_chek_order
FROm level1),
level3 as(SELECT *
       ,ROUND((sum_chek_order / count_item::numeric),2) as effect_per_order
FROM level2),
level4 as(SELECT DISTINCT customer_id, order_id
       ,count_item
	   ,sum_chek_order
	   ,effect_per_order
FROM level3),
level5 as(SELECT *
       ,ROUND(AVG(effect_per_order) OVER (partition by customer_id)::numeric,2) as avg_effect_per_order
	   ,ROUND(AVG(effect_per_order) OVER ()::numeric,2) as global_avg_effect
	   ,MIN(effect_per_order) OVER (partition by customer_id) as min_effect_per_order
	   ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by effect_per_order) FROM level4) as global_median_effect
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM level4)
SELECT *
FROM level5
WHERE count_order >= 6 AND avg_effect_per_order > global_avg_effect AND min_effect_per_order < global_median_effect

-- 403. «Клієнт з перекошеною структурою замовлень (ntile)»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,ntile(4) OVER (order by sum_chek) as global_ntile
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm level1),
level3 as(SELECT customer_id
       ,COUNT(order_id) FILTER (WHERE global_ntile = 1) as count_ntile_1
	   ,COUNT(order_id) FILTER (WHERE global_ntile = 2) as count_ntile_2
	   ,COUNT(order_id) FILTER (WHERE global_ntile = 3) as count_ntile_3
	   ,COUNT(order_id) FILTER (WHERE global_ntile = 4) as count_ntile_4
FROM level2
GROUP By customer_id),
level4 as(SELECT *
FROM level2
JOIN level3 USING (customer_id)
WHERE count_order >= 8 AND count_ntile_1 > 0 AND count_ntile_4 > 0
ORDER BY customer_id),
level5 as(SELECT *
       ,ROUND((count_ntile_1::numeric / count_order::numeric),2) as ratio_ntile_1
	   ,ROUND((count_ntile_2::numeric / count_order::numeric),2) as ratio_ntile_2
	   ,ROUND((count_ntile_3::numeric / count_order::numeric),2) as ratio_ntile_3
	   ,ROUND((count_ntile_4::numeric / count_order::numeric),2) as ratio_ntile_4
FROM level4),
level6 as(SELECT *
FROM level5
WHERE ratio_ntile_4 < 0.25),
level7 as(SELECT customer_id
       ,SUM(sum_chek) FILTER (WHERE global_ntile = 1) as total_chek_ntile_1
	   ,SUM(sum_chek) FILTER (WHERE global_ntile = 2) as total_chek_ntile_2
	   ,SUM(sum_chek) FILTER (WHERE global_ntile = 3) as total_chek_ntile_3
	   ,SUM(sum_chek) FILTER (WHERE global_ntile = 4) as total_chek_ntile_4
	   ,SUM(sum_chek) as total_chek_customer
FROm level6
GROUP By customer_id),
level8 as(SELECT *
FROM level6
JOIn level7 USING (customer_id)),
level9 as(SELECT *
       ,ROUND((total_chek_ntile_4 / total_chek_customer)::numeric,2) as ratio_ntile_4_in_total_chek
FROM level8)
SELECT *
FROm level9
WHERE ratio_ntile_4_in_total_chek > 0.5

       