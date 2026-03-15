-- 543. «Клієнт з ефектом втраченої інерції»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek,1) OVER (partition by customer_id order by order_date) as prev_1_chek
	   ,LAG(sum_chek,2) OVER (partition by customer_id order by order_date) as prev_2_chek
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,sum_chek - prev_1_chek as delta_1
	   ,prev_1_chek - prev_2_chek as delta_2 
FROm level2
WHERE prev_2_chek is not null),
level4 as(SELECT *
       ,case when (delta_1 > 0 AND delta_2 < 0) OR (delta_1 < 0 AND delta_2 > 0) THEN 1
	   ELSE 0 END as flag_delta
	   ,case when ABS(delta_1) >= ABS(2 * delta_2) THEN 1 ELSE 0 END as flag_abs_high
FROM level3),
level5 as(SELECT *
       ,SUM(flag_delta) OVER (partition by customer_id) as sum_flag_delta
	   ,SUM(flag_abs_high) OVER (partition by customer_id) as sum_flag_abs_high
FROM level4),
level6 as(SELECT *
       ,case when (delta_1 > 0 AND delta_2 > 0) OR (delta_1 < 0 AND delta_2 < 0) THEN 1
	   ELSE 0 end as flag_equal_delta
FROm level5
WHERE sum_flag_delta >= 1 AND sum_flag_abs_high >= 1),
level7 as(SELECT *
       ,LEAD(flag_equal_delta,1) OVER (partition by customer_id order by order_date) as next_1_equal_delta
	   ,LEAD(flag_equal_delta,2) OVER (partition by customer_id order by order_date) as next_2_equal_delta
FROm level6),
level8 as(SELECT *
       ,case when flag_equal_delta = 1 And next_1_equal_delta=1 AND next_2_equal_delta = 1 THEN 1
	   else 0 ENd as total_flag
FROm level7
WHERE next_2_equal_delta is not null)
SELECT *
FROm level8
WHERE total_flag = 1

-- 544. «Клієнт з ефектом помилкової нормалізації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,lag(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ABS(sum_chek - prev_chek) as delta
FROm level2),
level4 as(SELECT *
       ,MAX(delta) OVER (partition by customer_id) as max_delta
FROm level3),
level5 as(SELECT *
       ,MAX(case when delta = max_delta THEN order_date END) OVER (partition by customer_id) as date_max_delta
FROM level4),
level6 as(SELECT *
       ,case when order_date < date_max_delta THEN '1_before'
	   when order_date > date_max_delta THEN '2_after'
	   when order_date = date_max_delta THEN 'equal'
	   END as gradation
FROM level5),
level7 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = '1_before')::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = '2_after')::numeric,2) as avg_chek_after
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE gradation = '1_before')::numeric,2) as stddev_chek_before
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE gradation = '2_after')::numeric,2) as stddev_chek_after
FROM level6
WHERE gradation IN ('1_before', '2_after')
GROUP BY customer_id),
level8 as(SELECT *
       ,ROUND(ABS((avg_chek_after - avg_chek_before) / avg_chek_before)::numeric,2) as diff_chek 
FROM level7
WHERE avg_chek_before is not null AND avg_chek_after is not null
AND stddev_chek_before is not null AND stddev_chek_after is not null)
SELECT *
FROM level8
WHERE diff_chek <= 0.05 AND stddev_chek_after >= 1.5 * stddev_chek_before

-- 545. «Клієнт з ефектом зламаного ритму»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by interval) as median_interval
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,ABS(interval - median_interval) as abs_delta_interval
FROM level2
JOIN level3 USING(customer_id)),
level5 as(SELECT *
       ,MAX(abs_delta_interval) OVER (partition by customer_id) as max_abs_delta_interval
FROm level4),
level6 as(SELECT *
       ,MAX(case when abs_delta_interval = max_abs_delta_interval THEN order_date END) OVER (partition by customer_id) as date_max_interval
FROm level5),
level7 as(SELECT *
       ,case when order_date < date_max_interval THEN '1_before'
	   when order_date > date_max_interval THEN '2_after'
	   when order_date = date_max_interval THEN 'equal'
	   END as gradation
FROM level6),
level8 as(SELECT *
FROM level7
WHERE gradation IN ('1_before', '2_after')),
level9 as(SELECT customer_id
       ,gradation
	   ,percentile_cont(0.5) WITHIN GROUP (order by interval) as median_int
FROm level8
GROUP BY customer_id, gradation),
level10 as(SELECT *
FROm level8
JOIN level9 USING (customer_id, gradation)),
level11 as(SELECT customer_id
       ,ROUND(AVG(interval) FILTER (WHERE gradation = '1_before')::numeric,2) as avg_interval_before
	   ,ROUND(AVG(interval) FILTER (WHERE gradation = '2_after')::numeric,2) as avg_interval_after
	   ,ROUND(STDDEV(interval) FILTER (WHERE gradation = '1_before')::numeric,2) as stddev_interval_before
	   ,ROUND(STDDEV(interval) FILTER (WHERE gradation = '2_after')::numeric,2) as stddev_interval_after
	   ,AVG(median_int) FILTER (WHERE gradation = '1_before') as median_before
	   ,AVG(median_int) FILTER (WHERE gradation = '2_after') as median_after
FROm level10
GROUP BY customer_id),
level12 as(SELECT *
       ,ROUND(ABS((median_after - median_before) / median_before)::numeric,2) as diff_median
	   ,ROUND((stddev_interval_before / avg_interval_before)::numeric,2) as cv_before
	   ,ROUND((stddev_interval_after / avg_interval_after)::numeric,2) as cv_after
FROM level11
WHERE avg_interval_before is not null AND avg_interval_after is not null
AND stddev_interval_before is not null AND stddev_interval_after is not null)
SELECT *
FROm level12
WHERE diff_median <= 0.1 AND cv_after >= 1.5 * cv_before

-- 546. «Замовлення з ефектом “помилкової синхронізації”»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date,1) OVER (partition by customer_id order by order_date) as prev_1_date
	   ,LAG(order_date,2) OVER (partition by customer_id order by order_date) as prev_2_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_1_date as interval_1
	   ,prev_1_date - prev_2_date as interval_2
FROm level1
WHERE count_order >= 6 AND prev_2_date is not null),
level3 as(SELECT *
       ,case when interval_1 = interval_2 THEN 1 ELSE 0 END as flag_intervals
FROm level2),
level4 as(SELECT *
       ,SUM(flag_intervals) OVER (partition by customer_id) as sum_flag_intervals
FROm level3),
level5 as(SELECT *
       ,MIN(case when interval_1 = interval_2 THEN order_date ENd) OVER (partition by customer_id) as min_date_equal_interval
FROm level4
WHERE sum_flag_intervals >= 1),
level6 as(SELECT *
       ,case when order_date < min_date_equal_interval THEN 'before'
	   when order_date > min_date_equal_interval THEN 'after'
	   when order_date = min_date_equal_interval THEN 'equal'
	   END as gradation
FROm level5),
level7 as(SELECT *
       ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order_after
FROm level6
WHERE gradation = 'after'),
level8 as(SELECT *
       ,case when interval_1 <> interval_2 THEN 1
	   ELSE 0 END as flag_not_equal
	   ,MAX(interval_1) OVER (partition by customer_id) as max_interval
	   ,MIN(interval_1) OVER (partition by customer_id) as min_interval
FROm level7
WHERE count_order_after >= 3 AND rn <= 3),
level9 as(SELECT *
       ,sum(flag_not_equal) OVER (partition by customer_id) as sum_flag_not_equal
	   ,max_interval - min_interval as delta_interval
FROm level8)
SELECT *
FROm level9
WHERE sum_flag_not_equal = 3 AND delta_interval >= 20

-- 547. «Клієнт з ефектом хибної стабільності частоти»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USINg (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
FROm level2
WHERE interval is not null),
level4 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by interval) as median_interval
	   ,ROUND(AVG(interval)::numeric,2) as avg_interval
FROm level3
GROUP By customer_id),
level5 as(SELECT *
       ,ROUND(ABS((avg_interval - median_interval) / median_interval)::numeric,2) as diff_interval
FROm level3
JOIN level4 USING (customer_id)),
level6 as(SELECT *
       ,case when interval < median_interval THEN 'kurz'
	   when interval > median_interval THEN 'lange'
	   when interval = median_interval THEN 'equal'
	   END as gradation
FROm level5
WHERE diff_interval <= 0.1),
level7 as (SELECT *
       ,COUNT(order_id) OVER (partition by customer_id) as real_count_order
FROM level6
WHERE gradation IN ('kurz', 'lange')),
level8 as(SELECT customer_id
       ,COUNT(order_id) FILTER (WHERE gradation = 'kurz') as count_kurz
	   ,COUNT(order_id) FILTER (WHERE gradation = 'lange') as count_lange
FROM level7
GROUP BY customer_id),
level9 as(SELECT *
       ,ROUND((count_kurz::numeric / real_count_order::numeric),2) as ratio_kurz
	   ,ROUND((count_lange::numeric / real_count_order::numeric),2) as ratio_lange
FROM level7
JOIN level8 USING (customer_id))
SELECT *
FROm level9
WHERE ratio_kurz >= 0.4 AND ratio_lange >= 0.4

-- 548. «Клієнт з ефектом прихованого перевантаження»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,halfs
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,percentile_cont (0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROm level2
GROUP BY customer_id, halfs),
level4 as(SELECT customer_id
       ,ROUND(AVG(avg_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(avg_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,AVG(median_quantity) FILTER (WHERE halfs = 'first') as median_quantity_first
	   ,AVG(median_quantity) FILTER (WHERE halfs = 'second') as median_quantity_second
FROM level2
JOIN level3 USING (customer_id, halfs)
GROUP By customer_id),
level5 as(SELECT *
       ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,2) as diff_chek
FROm level4
WHERE median_quantity_second >= 1.5 * median_quantity_first)
SELECT *
FROm level5
WHERE diff_chek <= 0.05