-- 410. «Замовлення, яке зламало тренд»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition  by customer_id order by order_date) as prev_chek
FROM level1),
level3 as(SELECT *
       ,LAG(prev_chek) OVER (partition by customer_id order by order_date) as prev_2_chek
FROM level2),
level4 as (SELECT *
       ,sum_chek - prev_chek as delta1
	   ,prev_chek - prev_2_chek as delta2
FROM level3
WHERE prev_2_chek is not null),
level5 as(SELECT *
       ,case when (delta1 >0 AND delta2 <0) OR (delta1<0 AND delta2>0) THEN 1 ELSE 0 END as flag_delta
FROM level4
WHERE count_order >= 6),
level6 as(SELECT *
       ,SUM(flag_delta) OVER (partition by customer_id) as sum_flag_delta
FROM level5)
SELECT *
FROM level6
WHERE sum_flag_delta = 1

-- 411. «Клієнт із “звичним” другим замовленням»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta
FROM level2
where prev_chek is not null),
level4 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM level3),
level5 as(SELECT *
       ,case when rn = 1 THEN 'first_value'
	   when rn >= 2 THEN 'last_value'
	   END as gradation
FROM level4),
level6 as(SELECT customer_id
       ,gradation
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by delta)::numeric,2) as median
FROm level5
GROUP BY customer_id, gradation),
level7 as(SELECT *
FROM level5
JOIN level6 USING (customer_id, gradation)),
level8 as(SELECT customer_id
       ,ROUND(AVG(median) FILTER (WHERE gradation = 'first_value')::numeric,2) as median_first
	   ,ROUND(AVG(median) FILTER (WHERE gradation = 'last_value')::numeric,2) as median_last
FROM level7
GROUP BY customer_id)
SELECT *
FROM level8
WHERE median_first < median_last

-- 412. «Клієнт з ефектом “відскоку”»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROm level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta
FROM level2),
level4 as(select * 
       ,case when delta > 0 THEN 1 
	   when delta < 0 THEN 0 
	   END as flag_delta
FROM level3
WHERE prev_chek is not null),
level5 as(SELECT *
       ,LEAD(flag_delta) OVER (partition by customer_id order by order_date) as next_flag_delta
FROM level4),
level6 as(SELECt *
       ,case when flag_delta = 0 AND next_flag_delta = 1 THEN 1 ELSE 0 END as flag_two_delta
FROM level5
WHERE next_flag_delta is not null),
level7 as(SELECt *
       ,SUM(flag_two_delta) OVER (partition by customer_id) as sum_flag_two_delta
	   ,COUNT(order_id) FILTER (WHERE flag_delta = 0) OVER (partition by customer_id) as count_flag_0
FROM level6),
level8 as(SELECT *
       ,ROUND((sum_flag_two_delta::numeric / count_flag_0::numeric),2) as ratio 
FROM level7)
SELECT *
FROM level8
WHERE ratio >= 0.6

-- 413. «Клієнт з ефектом “охолодження”»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order 
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,sum_chek - prev_chek as prev_delta
	   ,next_chek - sum_chek as next_delta
FROM level2
WHERE prev_chek is not null AND next_chek is not null),
level4 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by prev_delta)::numeric,2) as median_delta
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
FROm level3
JOIN level4 USING (customer_id)),
level6 as(SELECT *
       ,case when prev_delta > median_delta AND prev_delta > 0 THEN 1 ELSE 0 END as flag_prev_delta
	   ,case when ABS(next_delta) < ABS(median_delta) THEN 1 ELSE 0 END as flag_next_delta
FROM level5),
level7 as(SELECT *
       ,COUNT(order_id) FILTER (WHERE flag_prev_delta = 1) OVER (partition by customer_id) as count_flag_prev_delta
	   ,COUNT(order_id) FILTER (WHERE flag_next_delta = 1) OVER (partition by customer_id) as count_flag_next_delta
FROM level6),
level8 as(SELECT *
       ,ROUND((count_flag_next_delta::numeric / count_flag_prev_delta::numeric),2) as cooldawn_rate
FROM level7
WHERE count_flag_prev_delta >= 3)
SELECT *
FROM level8
WHERE cooldawn_rate >= 0.6

-- 414. «Клієнт з короткими сплесками активності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 8),
level4 as(SELECT *
       ,case when sum_chek > median_chek THEN 0 ELSE 1 END as flag_chek
FROM level3),
level5 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id order by order_date) as sum_flag_chek
FROM level4),
level6 as(SELECT customer_id
       ,sum_flag_chek
	   ,COUNT(sum_flag_chek) as count_sum_flag_chek
FROM level5
GROUP BY customer_id, sum_flag_chek
ORDER BY customer_id),
level7 as(SELECT *
	   ,count_sum_flag_chek - 1 as real_count_sum_flag_chek
FROM level6),
level8 as(SELECT *
       ,COUNT(sum_flag_chek) FILTER (WHERE real_count_sum_flag_chek IN (1, 2)) OVER (partition by customer_id) as count_series
FROM level7)
SELECT *
FROm level8
WHERE count_series >= 2 AND real_count_sum_flag_chek IN (1,2)