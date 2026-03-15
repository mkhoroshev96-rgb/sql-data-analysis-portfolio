-- 496. «Клієнт з ефектом фальшивого покращення сервісу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,MAX(discount) as max_discount
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,shipped_date - order_date as delivery_days
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by delivery_days) as median_delivery
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
       ,case when delivery_days < median_delivery THEN 'pivot_date'
	   else 'other' END as flag_delivery
	   ,case when max_discount > 0 THEN 1 ELSE 0 END as flag_discount
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 6),
level4 as(SELECT *
       ,MIN(case when delivery_days < median_delivery THEN order_date END) OVER (partition by customer_id) as pivot_date
FROM level3),
level5 as(SELECT *
       ,case when order_date < pivot_date THEN 'before'
	   when order_date > pivot_date THEN 'after'
	   when order_date = pivot_date THEN 'pivot'
	   END as gradation 
FROM level4),
level6 as(SELECT customer_id
       ,ROUND(AVG(delivery_days) FILTER (WHERE gradation = 'before')::numeric,2) as avg_delivery_before
	   ,ROUND(AVG(delivery_days) FILTER (WHERE gradation = 'after')::numeric,2) as avg_delivery_after
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'before')::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'after')::numeric,2) as avg_chek_after
	   ,SUM(flag_discount) FILTER (WHERE gradation = 'before') as count_discount_before
	   ,SUM(flag_discount) FILTER (WHERE gradation = 'after') as count_discount_after
	   ,COUNT(order_id) FILTER (WHERE gradation = 'before') as count_order_before
	   ,COUNT(order_id) FILTER (WHERE gradation = 'after') as count_order_after
FROM level5
WHERE gradation IN ('before', 'after')
GROUP BY customer_id),
level7 as(SELECT *
       ,ROUND((count_discount_before::numeric / count_order_before::numeric),2) as ratio_before
	   ,ROUND((count_discount_after::numeric / count_order_after::numeric),2) as ratio_after
FROM level6
WHERE avg_delivery_before is not null AND avg_delivery_after is not null)
SELECT *
FROM level7
WHERE avg_delivery_after < avg_delivery_before AND avg_chek_after <= avg_chek_before
AND ratio_after > ratio_before

-- 497. «Клієнт з ефектом зворотної дисципліни»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,shipped_date - order_date as delivery_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by delivery_date) as median_delivery
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when delivery_date <= median_delivery THEN 'fast'
	   when delivery_date > median_delivery THEN 'slow'
	   END as gradation
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1
JOIN level2 USING (customer_id) 
WHERE count_order >= 7),
level4 as(SELECT *
       ,LEAD(gradation) OVER (partition by customer_id order by order_date) as next_gradation
	   ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as ratio_chek
FROM level3),
level5 as(SELECT *
       ,case when gradation = 'fast' AND next_gradation = 'slow' THEN 1 ELSE 0 END as flag_fast_slow
FROM level4
WHERE ratio_chek <= 0.08 AND next_gradation is not null),
level6 as(SELECT *
       ,SUM(flag_fast_slow) OVER (partition by customer_id) as sum_flag_fast_slow
       ,COUNT(order_id) FILTER (WHERE gradation = 'fast') OVER (partition by customer_id) as count_order_fast
FROM level5),
level7 as(SELECT *
       ,ROUND((sum_flag_fast_slow::numeric / count_order_fast::numeric),2) as ratio_fast_slow
FROM level6)
SELECT *
FROM level7
WHERE ratio_fast_slow > 0.5

-- 498. «Клієнт з ефектом помилкового контролю»

WITH block1 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when sum_quantity <= median_quantity THEN 'small'
	   when sum_quantity > median_quantity THEN 'large'
	   END as gradation
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 6),
level4 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROM level3),
level5 as(SELECT customer_id
       ,ROUND(AVG(next_chek) FILTER (WHERE gradation = 'small')::numeric,2) as avg_chek_after_small
	   ,ROUND(AVG(next_chek) FILTER (WHERE gradation = 'large')::numeric,2) as avg_chek_after_large
FROM level4
WHERE next_chek is not null
GROUP BY customer_id)
SELECT *
FROm level5
WHERE avg_chek_after_small > avg_chek_after_large AND avg_chek_after_small is not null
AND avg_chek_after_large is not null),
block2 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as order_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(order_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(order_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1)
SELECT DISTINCT customer_id
       ,avg_chek
	   ,global_avg_chek
FROM level2
WHERE avg_chek <= global_avg_chek)
SELECT *
FROm block1
JOIN block2 USING (customer_id)

-- 499. «Клієнт з ефектом короткої лояльності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,shipped_date - order_date as delivery_days
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by delivery_days) as median_delivery
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,case when delivery_days <= median_delivery THEN 'good_service'
	   when delivery_days > median_delivery THEN 'bad_dervice'
	   END as gradation
FROM level2
JOIN level3 USING (customer_id)),
level5 as(SELECT *
       ,LEAD(sum_chek,1) OVER (partition by customer_id order by order_date) as chek_after_good_1
	   ,LEAD(sum_chek,2) OVER (partition by customer_id order by order_date) as chek_after_good_2
FROm level4
WHERE count_order >= 7),
level6 as(SELECT *
       ,ROUND(AVG(chek_after_good_1) OVER (partition by customer_id)::numeric,2) as avg_chek_after_good_1
	   ,ROUND(AVG(chek_after_good_2) OVER (partition by customer_id)::numeric,2) as avg_chek_after_good_2
FROM level5
WHERE gradation = 'good_service' AND avg_chek > global_avg_chek)
SELECT *
FROM level6
WHERE avg_chek_after_good_1 > avg_chek AND avg_chek_after_good_1 > avg_chek_after_good_2

-- 500. «Клієнт з ефектом помилкової стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1- discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(avg(sum_chek)::numeric,2) as avg_chek
	   ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,ABS(sum_chek - avg_chek) as abs_deviation
	   ,ntile(3) over (partition by customer_id order by order_date) as ntile_3
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 8),
level4 as(SELECT customer_id
       ,ROUND(AVG(abs_deviation) FILTER (WHERE ntile_3 = 1)::numeric,2) as avg_abs_deviation_1
	   ,ROUND(AVG(abs_deviation) FILTER (WHERE ntile_3 = 2)::numeric,2) as avg_abs_deviation_2
	   ,ROUND(AVG(abs_deviation) FILTER (WHERE ntile_3 = 3)::numeric,2) as avg_abs_deviation_3
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
       ,ROUND(ABS((avg_chek - median_chek) / median_chek)::numeric,2) as diff_chek
FROM level3
JOIN level4 USING (customer_id))
SELECT *
FROM level5
WHERE diff_chek <= 0.05 AND avg_abs_deviation_2 > avg_abs_deviation_1 
AND avg_abs_deviation_2 > avg_abs_deviation_3

-- 501. «Клієнт з ефектом зламаної причинності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,shipped_date - order_date as delivery_days
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(delivery_days) OVER (partition by customer_id) as max_delivery
FROM level1
WHERE count_order >= 7),
level3 as(SELECT customer_id
       ,corr(sum_chek, delivery_days) as corr_chek_delivery
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,case when delivery_days = max_delivery THEN 'max_delivery'
	   ELSE 'other' END as gradation
FROM level2
JOIN level3 USING (customer_id)
WHERE corr_chek_delivery < 0),
level5 as(SELECT customer_id
       ,corr(sum_chek, delivery_days) FILTER (WHERE gradation = 'other') as corr_chek_delivery_other
FROM level4
GROUP BY customer_id),
level6 as(SELECT *
FROM level4
JOIN level5 USING (customer_id))
SELECT *
FROM level6
WHERE corr_chek_delivery_other >= 0