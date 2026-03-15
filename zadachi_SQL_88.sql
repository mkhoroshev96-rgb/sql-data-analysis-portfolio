-- 566. «Клієнт з ефектом зламаної стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level1
GROUP BY customer_id),
level3 as (SELECT *
       ,case when sum_chek > median_chek THEN 'above'
	   when sum_chek < median_chek THEN 'below'
	   when sum_chek = median_chek THEN 'equal'
	   END as gradation
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 6),
level4 as(SELECT *
       ,LAG(gradation) OVER (partition by customer_id order by order_date) as prev_gradation
FROM level3
WHERE gradation IN ('above', 'below')),
level5 as(SELECT *
       ,case when (gradation = 'below' AND prev_gradation = 'above') OR (gradation = 'above' AND prev_gradation = 'below') THEN 1
	   ELSE 0 END as flag_gradation
FROm level4
WHERE prev_gradation is not null),
level6 as(SELECT *
       ,SUM(flag_gradation) OVER (partition by customer_id) as sum_flag_gradation
	   ,COUNT(order_id) OVER (partition by customer_id) as real_count_order
FROM level5),
level7 as(SELECT *
       ,ROUND((sum_flag_gradation::numeric / real_count_order::numeric),2) as ratio
FROM level6)
SELECT *
FROM level7
WHERE ratio >= 0.5

-- 567. «Клієнт з ефектом локального максимуму»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when sum_chek > prev_chek AND sum_chek > next_chek THEN 1 
	   ELSE 0 END as local_max 
FROm level2
WHERE prev_chek is not null AND next_chek is not null),
level4 as(SELECT *
       ,sum(local_max) OVER (partition by customer_id) as sum_local_max
FROm level3),
level5 as(SELECT *
       ,MAX(case when local_max = sum_local_max THEN order_date END) OVER (partition by customer_id) as date_local_max
FROm level4
WHERE sum_local_max = 1),
level6 as(SELECT *
       ,case when order_date < date_local_max THEN 'before'
	   when order_date > date_local_max THEN 'after'
	   when order_date = date_local_max THEN 'local'
	   END as gradation
FROm level5),
level7 as(SELECT *
       ,MAX(sum_chek) FILTER (WHERE gradation = 'local') OVER (partition by customer_id) as max_chek
FROM level6),
level8 as(SELECT *
       ,case when sum_chek < max_chek THEn 1 ELSE 0 END as flag_peak_after
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order_after
FROm level7
WHERE gradation = 'after'),
level9 as(SELECT *
       ,SUM(flag_peak_after) OVER (partition by customer_id) as sum_flag_peak_after
FROm level8)
SELECT *
FROM level9
WHERE sum_flag_peak_after = count_order_after

-- 568. «Клієнт з ефектом зламаного відновлення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROm level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,case when prev_chek > sum_chek THEN 1 ELSE 0 END as flag_high_prev_chek
FROm level2),
level4 as(SELECT *
       ,MIN(case when prev_chek > sum_chek THEN order_date END) OVER (partition by customer_id) as first_date_high_prev_chek
FROm level3),
level5 as(SELECT *
       ,MAX(prev_chek) FILTER (WHERE order_date = first_date_high_prev_chek) OVER (partition by customer_id) as max_chek_first_date
	   ,case when order_date < first_date_high_prev_chek THEN 'before'
	   when order_date > first_date_high_prev_chek THEN 'after'
	   when order_date = first_date_high_prev_chek THEN 'local'
	   END as gradation
FROm level4
WHERE prev_chek is not null),
level6 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'before')::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'after')::numeric,2) as avg_chek_after
FROm level5
WHERE gradation IN ('before', 'after')
GROUP By customer_id),
level7 as(SELECT *
FROm level6
WHERE avg_chek_before is not null AND avg_chek_after is not null),
level8 as(SELECT *
FROM level5
JOIN level7 USING (customer_id)
WHERE avg_chek_after < avg_chek_before),
level9 as(SELECT *
       ,case when sum_chek < max_chek_first_date THEN 1 ELSE 0 END as flag_after_peak
	   ,COUNT(order_id) FILTER (WHERE gradation = 'after') OVER (partition by customer_id) as count_order_after 
FROM level8
WHERE gradation = 'after'),
level10 as(SELECT *
       ,SUM(flag_after_peak) OVER (partition by customer_id) as sum_flag_after_peak
from level9)
SELECT *
FROm level10
WHERE count_order_after = sum_flag_after_peak

-- 569. «Клієнт з ефектом помилкового відновлення»

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
FROm level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,case when prev_chek > sum_chek THEN 1 ELSE 0 END as high_prev_chek
FROm level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,MIN(case when prev_chek > sum_chek THEN order_date END) OVER (partition by customer_id) as first_date_fall
FROm level3),
level5 as(SELECT *
       ,case when order_date < first_date_fall THEN 'before'
	   when order_date > first_date_fall THEN 'after'
	   when order_date = first_date_fall THEN 'fall'
	   END as gradation
	   ,MAX(prev_chek) FILTER (WHERE order_date = first_date_fall) OVER (partition by customer_id) as max_prev_chek
FROM level4),
level6 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'before') OVER (partition by customer_id)::numeric,2) as avg_chek_before_fall
FROm level5),
level7 as(SELECT *
       ,case when sum_chek >= max_prev_chek THEN 1 ELSE 0 END as flag_recovery
FROM level6
WHERE gradation = 'after'),
level8 as(SELECT *
       ,MIN(case when sum_chek >= max_prev_chek THEN order_date END) OVER (partition by customer_id) as first_date_after_recovery 
FROm level7),
level9 as(SELECT *
       ,case when order_date < first_date_after_recovery THEN 'bevor_recovery'
	   when order_date > first_date_after_recovery THEN 'after_recovery'
	   when order_date = first_date_after_recovery THEN 'recovery'
	   END as gradation_recovery
FROm level8),
level10 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation_recovery = 'after_recovery') OVER (partition by customer_id)::numeric,2) as avg_chek_after_recovery
FROM level9),
level11 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id Order by order_date DESC) as rn_invert
FROm level10
WHERE avg_chek_after_recovery < avg_chek_before_fall),
level12 as(SELECT *
       ,ROUND(avg(sum_chek) FILTER (where rn_invert = 1) OVER (partition by customer_id)::numeric,2) as last_chek
	   ,ROUND(avg(sum_chek) FILTER (where rn_invert = 2) OVER (partition by customer_id)::numeric,2) as prev_last_chek
FROm level11)
SELECT *
FROm level12
WHERE max_prev_chek > last_chek AND max_prev_chek > prev_last_chek

-- 570. «Замовлення з ефектом інерції рішення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity 
	   ,ROUND(SUM (unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,ROUND((sum_chek / sum_quantity)::numeric,2) as price
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as stddev_chek
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ABS(sum_chek - prev_chek) as abs_delta_chek
	   ,ABS(sum_quantity - prev_quantity) as abs_delta_quantity
FROM level2
WHERE prev_quantity is not null),
level4 as(SELECT *
       ,LAG(price) OVER (partition by customer_id order by order_date) as prev_price 
FROm level3),
level5 as(SELECT *
       ,ROUND(ABS((price - prev_price) / prev_price)::numeric,2) as diff_price
FROM level4)
SELECT *
FROm level5
WHERE abs_delta_chek < stddev_chek AND abs_delta_quantity = 0 
AND diff_price >= 0.1

-- 571. «Замовлення з ефектом відкладеного удару»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as stddev_chek
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when sum_chek > avg_chek AND next_chek < avg_chek AND next_chek < sum_chek THEN 1 
	   ELSE 0 END as flag_chek
	   ,ABS(sum_chek - next_chek) as abs_delta_chek
FROm level2
WHERE next_chek is not null)
SELECT *
FROM level3
WHERE flag_chek = 1 AND abs_delta_chek > stddev_chek