-- 383. «Ілюзія стабільного клієнта»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROm level1),
level3 as(SELECT *
       ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_chek
FROm level2),
level4 as(SELECT *
       ,ROUND((sum_chek / avg_chek)::numeric,2) as ratio_chek
FROM level3
WHERE diff_chek <= 0.1),
level5 as(SELECT *
       ,case when ratio_chek >= 1.5 THEN 1 ELSE 0 END as flag_high_chek
	   ,case when ratio_chek <= 0.5 THEN 1 ELSE 0 END as flag_low_chek
FROM level4),
level6 as(SELECT *
       ,SUM(flag_high_chek) OVER (partition by customer_id) as sum_flag_high_chek
	   ,SUM(flag_low_chek) OVER (partition by customer_id) as sum_flag_low_chek
FROm level5)
SELECT *
FROm level6
WHERE sum_flag_high_chek >= 1 AND sum_flag_low_chek >= 1

-- 384. «Ілюзія лояльності через повторюваність»

WITH block1 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,COUNT(product_id) OVER (partition by customer_id) as total_count_product
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,COUNT(DISTINCT product_id) as count_unik_prod
FROM level1
GROUP By customer_id)
SELECT *
       ,ROUND((count_unik_prod::numeric / total_count_product::numeric),2) as ratio
FROM level1
JOIN level2 USING (customer_id)),
block2 as(WITH level1 as(SELECT customer_id
	   ,COUNT(order_id) as count_order
FROm orders
GROUP By customer_id),
level2 as(SELECT *
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by count_order) FROM level1) as median_count_order
FROM level1)
SELECT *
FROm level2)
SELECT *
FROM block1
JOIN block2 USING (customer_id)
WHERE count_order > median_count_order AND ratio <= 0.3

-- 385. «Ілюзія зростання без зростання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2),2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROm level1
WHERE count_order >= 4),
level3 as(SELECT customer_id
       ,halfs
	   ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
	   ,MAX(sum_chek) as max_chek
FROm level2
GROUP BY customer_id, halfs),
level4 as(SELECT *
FROM level2
JOIN level3 USING (customer_id, halfs)),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_chek_second
	   ,ROUND(AVG(median_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as median_chek_first
	   ,ROUND(AVG(median_chek) FILTER (WHERE halfs = 'second_half')::numeric,2) as median_chek_second
	   ,ROUND(AVG(max_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as max_chek_first
	   ,ROUND(AVG(max_chek) FILTER (WHERE halfs = 'second_half')::numeric,2) as max_chek_second
FROM level4
GROUP By customer_id)
SELECT *
FROM level5
WHERE avg_chek_second > avg_chek_first 
AND median_chek_second <= median_chek_first
AND max_chek_second <= max_chek_first

-- 386. «Парадокс середнього по країні»

WITH level1 as(SELECT ship_country
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROUND(AVG(unit_price * (1-discount)) ::numeric,2) as avg_price
	   ,COUNT(order_id) OVER (partition by ship_country) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by ship_country)::numeric,2) as avg_chek_country
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
	   ,ROUND(AVG(avg_price) OVER (partition by ship_country)::numeric,2) as avg_price_country
	   ,ROUND(AVG(avg_price) OVER ()::numeric,2) as global_avg_price
FROm level1
WHERE count_order > 10),
level3 as(SELECT *
       ,ROUND((avg_chek_country / global_avg_chek)::numeric,2) as diff_avg_chek
	   ,ROUND((avg_price_country / global_avg_price)::numeric,2) as diff_avg_price
FROm level2)
SELECT *
FROM level3
WHERE diff_avg_chek <= 0.85 AND diff_avg_price >= 1.1

-- 387. «Клієнт, який ЗДАЄТЬСЯ вигідним»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1
WHERE count_order >= 5)
SELECT *
FROM level2
WHERE avg_chek >= global_avg_chek

WITh level1 as(SELECT customer_id
       ,category_id
	   ,order_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROUND(AVG(discount)::numeric,2) as avg_discount
FROM orders
JOIN order_details USING(order_id)
JOIN products p USING (product_id)
JOIN categories USING(category_id)
GROUP By customer_id, category_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by category_id)::numeric,2) as avg_chek_category
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
	   ,ROUND(AVG(avg_discount) OVER (partition by category_id)::numeric,2) as avg_discount_category
	   ,ROUND(AVG(avg_discount) OVER ()::numeric,2) as global_avg_discount
FROM level1)
SELECT *
FROM level2
WHERE avg_chek_category < global_avg_chek AND avg_discount_category > global_avg_discount

-- 388. «Клієнти з псевдостабільністю чека та різким зламом»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROm level1),
level3 aS(SELECT *
       ,LEAD(next_chek) OVER (partition by customer_id order by order_date) as next_2_chek
FROm level2),
level4 as(SELECT *
       ,LEAD(next_2_chek) OVER (partition by customer_id order by order_date) as next_3_chek
FROM level3),
level5 as(SELECT *
       ,LEAD(next_3_chek) OVER (partition by customer_id order by order_date) as next_4_chek
FROm level4),
level6 as(SELECT *
       ,ROUND(ABS((next_chek - sum_chek) / next_chek)::numeric,2) as diff_1
	   ,ROUND(ABS((next_2_chek - next_chek) / next_2_chek)::numeric,2) as diff_2
	   ,ROUND(ABS((next_3_chek - next_2_chek) / next_3_chek)::numeric,2) as diff_3
	   ,ROUND(ABS((next_4_chek - next_3_chek) / next_4_chek)::numeric,2) as diff_4
FROm level5
WHERE next_4_chek is not null),
level7 as(SELECT *
       ,case when diff_1 <= 0.05 THEN 1 ELSE 0 END as gradation_1
	   ,case when diff_2 <= 0.05 THEN 1 ELSE 0 END as gradation_2
	   ,case when diff_3 <= 0.05 THEN 1 ELSE 0 END as gradation_3
	   ,case when diff_4 > 0.2 THEN 1 ELSE 0 END as gradation_4
FROm level6),
level8 as(SELECT *
       ,case when gradation_1 = 1 AND gradation_2 = 1 AND gradation_3 = 1 AND gradation_4 = 1 THEN 1
	   ELSE 0 END as total_gradation  
FROM level7)
SELECT *
FROM level8
WHERE total_gradation = 1

