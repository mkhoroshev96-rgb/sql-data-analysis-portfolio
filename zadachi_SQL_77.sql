-- 490. «Клієнт з ефектом помилкової адаптації»

WITH block1 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
FROM level1
WHERE count_order >= 7),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,case when sum_quantity > median_quantity THEN 'high'
	   when sum_quantity < median_quantity THEN 'low'
	   when sum_quantity = median_quantity THEN 'normal'
	   END as flag_quantity
	   ,case when sum_chek > median_chek THEN 'high'
	   when sum_chek < median_chek THEN 'low'
	   when sum_chek = median_chek THEN 'normal'
	   END as flag_chek
FROM level2
JOIN level3 USING (customer_id)),
level5 as(SELECT *
       ,LEAD(flag_quantity) OVER (partition by customer_id order by order_date) as next_flag_qnt
	   ,LEAD(flag_chek) OVER (partition by customer_id order by order_date) as next_flag_chek
FROM level4
WHERE flag_quantity <> 'normal' AND flag_chek <> 'normal'),
level6 as(SELECT *
       ,LEAD(next_flag_qnt) OVER (partition by customer_id order by order_date) as next_2_flag_qnt
	   ,LEAD(next_flag_chek) OVER (partition by customer_id order by order_date) as next_2_flag_chek
FROM level5),
level7 as(SELECT *
       ,case when flag_chek = 'high' AND next_flag_chek = 'low' AND next_2_flag_chek = 'low' THEN 1
	   ELSE 0 END as sequence_chek
	   ,case when flag_quantity = 'high' AND next_flag_qnt = 'high' AND next_2_flag_qnt = 'low' THEN 1
	   ELSE 0 END as sequence_quantity
FROM level6),
level8 as(SELECT *
       ,case when sequence_chek = 1 AND sequence_quantity = 1 THEN 1 ELSE 0 END as total_sequence
FROM level7),
level9 as(SELECT *
       ,SUM(total_sequence) OVER (partition by customer_id) as sum_total_sequence
FROM level8)
SELECT *
FROM level9
WHERE sum_total_sequence >= 2),
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
FROM level2),
block3 as(SELECT *
       ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as ratio
FROM block1
JOIN block2 USING (customer_id))
SELECT *
FROM block3
WHERE ratio <= 0.07

-- 491. «Клієнт з ефектом помилкового покращення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,MIN(case when sum_chek = min_chek THEN order_date END) OVER (partition by customer_id) as date_break
FROM level2),
level4 as(SELECT *
       ,case when order_date < date_break THEN '1_before'
	   when order_date > date_break THEN '2_after'
	   when order_date = date_break THEN 'break'
	   END as gradation
FROM level3),
level5 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id, gradation order by order_date) as rn_after
	   ,ROW_NUMBER () OVER (partition by customer_id, gradation order by order_date DESC) as rn_before
	   ,COUNT(order_id) FILTER (WHERE gradation = '1_before') OVER (partition by customer_id) as count_order_before
	   ,COUNT(order_id) FILTER (WHERE gradation = '2_after') OVER (partition by customer_id) as count_order_after
FROM level4
WHERE gradation IN ('1_before', '2_after')),
level6 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = '1_before' AND rn_before <= 2)::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = '2_after' AND rn_after <= 2)::numeric,2) as avg_chek_after
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE gradation = '1_before' AND rn_before <= 2)::numeric,2) as avg_quantity_before
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE gradation = '2_after' AND rn_after <= 2)::numeric,2) as avg_quantity_after
FROM level5
WHERE count_order_before >= 2 AND count_order_after >= 2
GROUP BY customer_id)
SELECT *
FROM level6
WHERE avg_chek_after > avg_chek_before AND avg_quantity_after <= avg_quantity_before

-- 492. «Клієнт з ефектом вибіркової пам’яті»

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
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when sum_chek > median_chek THEN 'good_exp'
	   when sum_chek < median_chek THEN 'bad_exp'
	   when sum_chek = median_chek THEN 'norm_exp'
	   END as gradation
FROM level1
JOIN level2 USING (customer_id)),
level4 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROM level3
WHERE gradation IN ('good_exp', 'bad_exp')),
level5 as(SELECT customer_id
       ,ROUND(AVG(next_chek) FILTER (WHERE gradation = 'good_exp')::numeric,2) as avg_chek_after_good
	   ,ROUND(AVG(next_chek) FILTER (WHERE gradation = 'bad_exp')::numeric,2) as avg_chek_after_bad
FROM level4
WHERE next_chek is not null
GROUP BY customer_id)
SELECT *
FROM level5
WHERE avg_chek_after_good <= avg_chek_after_bad

-- 493. «Клієнт з ефектом короткої пам’яті»

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
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when sum_chek > median_chek THEN 'high'
	   when sum_chek < median_chek THEN 'low'
	   when sum_chek = median_chek THEN 'normal'
	   END as gradation
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 7),
level4 as(SELECT *
       ,LEAD(sum_chek,1) OVER (partition by customer_id order by order_date) as chek_after_1
	   ,LEAD(sum_chek,2) OVER (partition by customer_id order by order_date) as chek_after_2
FROM level3),
level5 as(SELECT *
FROM level4
WHERE chek_after_2 is not null and gradation = 'high'),
level6 as(SELECT customer_id
       ,ROUND(AVG(chek_after_1)::numeric,2) as avg_chek_after_1
	   ,ROUND(AVG(chek_after_2)::numeric,2) as avg_chek_after_2
FROM level5
GROUP BY customer_id),
level7 as(SELECT *
       ,ROUND(ABS((avg_chek_after_1 - avg_chek_after_2) / avg_chek_after_2)::numeric,2) as ratio
FROM level6
WHERE avg_chek_after_1 > avg_chek_after_2)
SELECT *
FROM level7
WHERE ratio >= 0.1

-- 494. «Клієнт з ефектом зламаного очікування»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > avg_chek THEN 'above_avg'
	   when sum_chek < avg_chek THEN 'below_avg'
	   when sum_chek = avg_chek THEN 'normal_avg'
	   END as gradation
FROM level2
WHERE count_order >= 6),
level4 as(SELECT *
       ,LEAD(gradation) OVER (partition by customer_id order by order_date) as next_gradation
FROM level3),
level5 as(SELECT *
       ,LEAD(next_gradation) OVER (partition by customer_id order by order_date) as next_2_gradation
FROM level4),
level6 as (SELECT *
       ,case when gradation = 'above_avg' AND next_gradation = 'below_avg' AND next_2_gradation = 'below_avg' THEN 1 
	   ELSE 0 END as flag_gradation
FROM level5),
level7 as(SELECT *
       ,SUM(flag_gradation) OVER (partition by customer_id) as sum_flag_gradation
FROM level6),
level8 as(SELECT *
       ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_chek
FROM level7
WHERE sum_flag_gradation >= 3)
SELECT *
FROM level8
WHERE diff_chek < 0.1

-- 495. «Клієнт з ефектом втраченої інерції»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta_chek
FROM level2),
level4 as (SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_last
FROM level3
WHERE delta_chek is not null),
level5 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by delta_chek)::numeric,2) as median_delta
FROM level4
GROUP BY customer_id),
level6 as(SELECT *
       ,AVG(delta_chek) FILTER (WHERE rn_last = 1) OVER (partition by customer_id) as delta_1
	   ,AVG(delta_chek) FILTER (WHERE rn_last = 2) OVER (partition by customer_id) as delta_2
	   ,AVG(delta_chek) FILTER (WHERE rn_last = 3) OVER (partition by customer_id) as delta_3
FROM level4
JOIN level5 USING (customer_id)
WHERE median_delta > 0),
level7 as(SELECT *
       ,case when delta_1 < 0 AND delta_2 < 0 AND delta_3 < 0 THEN 'yes'
	   ELSE 'no' END as flag_delta
FROm level6)
SELECT *
FROM level7
WHERE flag_delta = 'yes'
