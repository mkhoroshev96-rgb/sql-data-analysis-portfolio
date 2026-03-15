-- 428. «Клієнт із “пам’яттю” на знижку»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND((sum(unit_price * quantity * discount)::numeric)/(SUM(unit_price * quantity)::numeric),4) as order_discount
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(order_discount) OVER (partition by customer_id order by order_date) as prev_discount
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,order_discount - prev_discount as delta_discount
       ,ABS(order_discount - prev_discount) as abs_delta_discount
FROM level2
WHERE prev_discount is not null),
level4 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by abs_delta_discount) as median_discount
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
       ,LAG(delta_discount) OVER (Partition by customer_id order by order_date) as prev_delta
FROM level3
JOIN level4 USING (customer_id)),
level6 as(SELECT *
       ,case when (delta_discount < 0 AND prev_delta < 0) OR (delta_discount = 0 AND prev_delta = 0) OR (delta_discount > 0 AND prev_delta > 0) THEN 1
	   ELSE 0 END as gradation
	   ,count_order - 2 as real_count_order
FROM level5
WHERE prev_delta is not null),
level7 as(SELECT *
       ,SUM(gradation) OVER (partition by customer_id) as sum_gradation
FROm level6),
level8 as(SELECT *
       ,ROUND((sum_gradation::numeric / real_count_order::numeric),2) as diff
FROm level7),
level9 as(SELECT *
       ,LEAD(delta_discount) OVER (partition by customer_id ORDER BY order_date) as next_delta
FROM level8
WHERE diff >= 0.7),
level10 as(SELECT *
       ,LEAD(delta_discount) OVER (partition by customer_id ORDER BY order_date) as next_2_delta
FROM level9),
level11 as(SELECT *
FROM level10
WHERE next_delta is not null AND next_2_delta is not null)
SELECT *
FROm level11
WHERE abs_delta_discount >= 3 * median_discount

-- 429. «Клієнт із “зламаною стабільністю”»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as order_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(order_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ABS(order_chek - prev_chek) as abs_delta_chek
FROM level2),
level4 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by order_chek) as median_chek
	   ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by abs_delta_chek)::numeric,2) as median_delta
FROm level3
GROUP BY customer_id),
level5 as(SELECT *
       ,case when ABS(order_chek - median_chek) >= 3 * median_delta THEN 1 ELSE 0 END as flag_break
FROM level3
JOIN level4 USING (customer_id)),
level6 as(SELECT *
       ,SUM(flag_break) OVER (partition by customer_id) as sum_flag_break
FROm level5),
level7 as(SELECT *
       ,MAX(case when flag_break = sum_flag_break THEN order_date END) OVER (partition by customer_id) as date_break
FROM level6
WHERE sum_flag_break = 1),
level8 as(SELECT *
       ,case when order_date < date_break THEN 'before'
	   when order_date = date_break THEN 'break'
	   when order_date > date_break THEN 'after'
	   END as groups
FROM level7),
level9 as(SELECT *
       ,case when (order_chek - median_chek) > 0 THEN 1 ELSE 0 END as flag_chek_plus
	   ,case when (order_chek - median_chek) < 0 THEN 1 ELSE 0 END as flag_chek_minus
	   ,COUNT(order_id) OVER (partition by customer_id) as real_count
FROM level8
WHERE groups = 'after'),
level10 as(SELECT *
       ,SUM(flag_chek_plus) OVER (partition by customer_id) as sum_flag_chek_plus
	   ,SUM(flag_chek_minus) OVER (partition by customer_id) as sum_flag_chek_minus
FROM level9)
SELECT *
FROM level10
WHERE real_count = sum_flag_chek_plus OR real_count = sum_flag_chek_minus

-- 430. «Клієнт-спринтер»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id ORDER BY order_date) as prev_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders),
level2 as(SELECT *
       ,order_date - prev_date as gap
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by gap) as median_gap
FROM level2
GROUP By customer_id),
level4 as(SELECT *
FROM level2
JOIn level3 USING (customer_id)),
level5 as(SELECT *
       ,LEAD(gap) OVER (partition by customer_id order by order_date) as next_gap
FROM level4),
level6 as(SELECT *
       ,LEAD(next_gap) OVER (partition by customer_id order by order_date) as next_2_gap
FROM level5),
level7 as(SELECT *
       ,(gap + next_gap + next_2_gap)/3 as avg_3_gap
	   ,LEAD(next_2_gap) OVER (partition by customer_id order by order_date) as next_3_gap
FROm level6
WHERE next_2_gap is not null and gap is not null),
level8 as(SELECT *
FROM level7
WHERE avg_3_gap <= 0.4 * median_gap AND next_3_gap is not null)
SELECT *
FROM level8
WHERE next_3_gap >= median_gap

-- 431. «Клієнт-ехо»

WITH level1 as (SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING(order_id) 
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
FROm level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
FROM level2
JOIN level3 USING (customer_id)),
level5 as(SELECT *
       ,case when sum_quantity > median_quantity THEN 'high'
	   when sum_quantity < median_quantity THEN 'low'
	   when sum_quantity = median_quantity THEN 'equal'
	   END as gradation
	   ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROm level4),
level6 as(SELECT *
       ,case when prev_quantity > median_quantity THEN 'high'
	   when prev_quantity < median_quantity THEN 'low'
	   when prev_quantity = median_quantity THEN 'equal'
	   END as prev_gradation
FROM level5
WHERE prev_quantity is not null),
level7 as(SELECT *
       ,case when gradation = prev_gradation THEN 1 ELSE 0 END as flag_gradation
FROm level6
WHERE prev_gradation IN ('high','low') AND gradation IN ('high','low')),
level8 as(SELECT *
       ,SUM(flag_gradation) OVER (partition by customer_id) as sum_flag_gradation
	   ,COUNT(order_id) OVER (partition by customer_id) as real_count_order
FROm level7),
level9 as(SELECT *
       ,ROUND((sum_flag_gradation::numeric / real_count_order::numeric),2) as echo_rate
FROm level8)
SELECT *
FROM level9
WHERE echo_rate >= 0.7 AND real_count_order >= 4
