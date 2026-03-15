-- 536. «Клієнт з ефектом хибного покращення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((sum_chek / sum_quantity)::numeric,2) as avg_price
FROm level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LAG(avg_price) OVER (partition by customer_id order by order_date) as prev_price
FROM level2),
level4 as(SELECT *
       ,case when sum_quantity > prev_quantity THEN 1 ELSE 0 END as flag_quantity
	   ,case when sum_chek > prev_chek THEN 1 ELSE 0 END as flag_chek
	   ,case when avg_price < prev_price THEN 1 ELSE 0 END as flag_price
	   ,count_order - 1 as real_count_order
FROM level3),
level5 as(SELECT *
       ,SUM(flag_quantity) OVER (partition by customer_id) as sum_flag_quantity
	   ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
	   ,SUM(flag_price) OVER (partition by customer_id) as sum_flag_price
FROM level4),
level6 as(SELECT *
       ,ROUND((sum_flag_quantity::numeric / real_count_order::numeric),2) as ratio_quantity
	   ,ROUND((sum_flag_chek::numeric / real_count_order::numeric),2) as ratio_chek
	   ,ROUND((sum_flag_price::numeric / real_count_order::numeric),2) as ratio_price
FROM level5)
SELECT *
FROM level6
WHERE ratio_quantity >= 0.5 AND ratio_chek >= 0.5 AND ratio_price >= 0.5

-- 537. «Клієнт з ефектом інерційного вибору»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date
ORDER BY customer_id),
level2 as(SELECT customer_id
       ,sum_quantity
       ,COUNT(sum_quantity) as mode_quantity
FROM level1
GROUP BY customer_id, sum_quantity),
level3 as(SELECT *
       ,MAX(mode_quantity) OVER (partition by customer_id) as max_mode_quantity
FROM level1
JOIN level2 USING (customer_id, sum_quantity)),
level4 as(SELECT *
       ,ROUND((max_mode_quantity::numeric / count_order::numeric),2) as ratio_mode
FROm level3
WHEre  max_mode_quantity >= 2 AND count_order >= 6)
SELECT *
FROm level4
WHERE ratio_mode > 0.5

-- 538. «Клієнт з ефектом вибіркової памʼяті»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN group (order by sum_chek) as median_chek
FROm level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when sum_chek >= median_chek THEN 'high'
	   when sum_chek < median_chek THEN 'low'
	   END as gradation
	   ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROM level1
JOIn level2 USING (customer_id)
WHERE count_order >= 7),
level4 as(SELECT *
       ,ABS(sum_quantity - prev_quantity) as abs_delta 
FROm level3),
level5 as(SELECT customer_id
       ,ROUND(AVG(abs_delta) FILTER (WHERE gradation = 'high')::numeric,2) as avg_abs_delta_high
	   ,ROUND(AVG(abs_delta) FILTER (WHERE gradation = 'low')::numeric,2) as avg_abs_delta_low
FROm level4
GROUP BY customer_id)
SELECT *
FROm level5
WHERE avg_abs_delta_high > avg_abs_delta_low

-- 539.  «Клієнт з ефектом сліпої зони»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders 
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.25) WITHIN GROUP (order by sum_chek) as percentile_25
	   ,percentile_cont(0.75) WITHIN GROUP (order by sum_chek) as percentile_75
FROm level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when sum_chek < percentile_25 OR sum_chek > percentile_75 THEN 'extreme'
	   when sum_chek between percentile_25 AND percentile_75 THEN 'normal'
	   END as gradation
	   ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 8),
level4 as(SELECT *
       ,ABS(sum_quantity - prev_quantity) as abs_delta
FROm level3
WHERE prev_quantity is not null),
level5 as(SELECT customer_id
       ,ROUND(AVG(abs_delta) FILTER (WHERE gradation = 'normal')::numeric,2) as avg_abs_delta_normal
	   ,ROUND(AVG(abs_delta) FILTER (WHERE gradation = 'extreme')::numeric,2) as avg_abs_delta_extreme
FROM level4
GROUP BY customer_id),
level6 as(SELECT *
       ,ROUND(ABS((avg_abs_delta_normal - avg_abs_delta_extreme) / avg_abs_delta_normal)::numeric,2) as diff_delta
FROM level5)
SELECT *
FROm level6
WHERE diff_delta <= 0.1

-- 540. «Клієнт з ефектом ламаної причинності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,LEAD(sum_quantity,1) OVER (partition by customer_id order by order_date) as next_1_quantity
	   ,LEAD(sum_quantity,2) OVER (partition by customer_id order by order_date) as next_2_quantity
FROM level1
WHERE count_order >= 9),
level3 as(SELECT *
       ,sum_quantity - next_1_quantity as delta_1_quantity
	   ,sum_quantity - next_2_quantity as delta_2_quantity
	   ,case when sum_chek > avg_chek THEN 'high'
	   else 'other' END as gradation
FROm level2),
level4 as(SELECT *
       ,case when ABS(next_1_quantity - sum_quantity) = 0 THEN 1 ELSE 0 END as flag_next_1
	   ,case when ABS(next_2_quantity - next_1_quantity) > 0 THEN 1 ELSE 0 END as flag_next_2
FROm level3
WHERE gradation = 'high' AND next_2_quantity is not null)
SELECT *
FROM level4
WHERE flag_next_1 = 1 AND flag_next_2 = 1

-- 541. «Клієнт з ефектом перевернутої стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROm level1
GROUP By customer_id),
level3 as(SELECT *
       ,ROUND(ABS((avg_chek - median_chek) / median_chek)::numeric,2) as diff_chek
FROm level1
JOIN level2 USING (customer_id)
WHERE count_order >= 6),
level4 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROm level3
WHERE diff_chek <= 0.05),
level5 as(SELECT *
       ,case when sum_chek > prev_chek THEN 'high'
	   when sum_chek < prev_chek THEN 'low'
	   when sum_chek = prev_chek THEN 'equal'
	   END as gradation
FROm level4
WHERE prev_chek is not null),
level6 as(SELECT *
       ,LAG(gradation) OVER (partition by customer_id order by order_date) as prev_gradation
FROm level5),
level7 as(SELECT *
       ,case when (gradation = 'high' AND prev_gradation = 'low') OR (gradation = 'low' AND prev_gradation = 'high') THEN 1
	   ELSE 0 END as flag_gradation
	   ,COUNT(order_id) OVER (partition by customer_id) as real_count_order
FROm level6
WHERE prev_gradation is not null),
level8 as(SELECT *
       ,SUM(flag_gradation) OVER (partition by customer_id) as sum_flag_gradation
FROM level7),
level9 as(SELECT *
       ,ROUND((sum_flag_gradation::numeric / real_count_order::numeric),2) as ratio_gradation
FROm level8)
SELECT *
FROm level9
WHERE ratio_gradation >= 0.6

-- 542. «Клієнт з ефектом локального максимуму»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when sum_chek > prev_chek AND sum_chek > next_chek THEN 1 ELSE 0 END as flag_chek
FROm level2
WHERE prev_chek is not null AND next_chek is not null),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROm level3),
level5 as(SELECT *
       ,AVG(sum_chek) FILTER (WHERE flag_chek = 1) OVER (partition by customer_id) as local_high_chek
FROm level4
WHERE sum_flag_chek = 1)
SELECT *
FROm level5
WHERE local_high_chek >= 1.5 * avg_chek