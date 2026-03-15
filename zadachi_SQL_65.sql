-- 415. «Клієнт з ефектом повтору»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(sum(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta
FROm level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,ROUND((ABS(delta) / prev_chek)::numeric,2) as diff
FROM level3),
level5 as(SELECT *
       ,case when diff <= 0.1 THEN 1 ELSE 0 END as flag_diff
	   ,count_order - 1 as real_count_order
FROM level4),
level6 as(SELECT *
       ,SUM(flag_diff) OVER (partition by customer_id) as sum_flag_diff
FROM level5),
level7 as(SELECT *
       ,ROUND((sum_flag_diff::numeric / real_count_order::numeric),2) as ratio_diff
FROM level6)
SELECT *
FROM level7
WHERE ratio_diff >= 0.6

-- 416. «Клієнт з ефектом локальної стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id,order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta
	   ,count_order - 1 as real_count_order
FROM level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,ROUND((ABS(delta) / prev_chek)::numeric,2) as diff_delta
FROM level3),
level5 as(SELECT *
       ,case when diff_delta <= 0.1 THEN 1 ELSE 0 END as flag_delta
FROM level4),
level6 as(SELECT *
       ,SUM(flag_delta) OVER (partition by customer_id) as sum_flag_delta
FROM level5),
level7 as(SELECT *
       ,ROUND((sum_flag_delta::numeric / real_count_order::numeric),2) as ratio_diff
FROM level6),
level8 as(SELECT *
       ,case when diff_delta <= 0.1 THEN 0 ELSE 1 END as flag_series
FROM level7
WHERE ratio_diff < 0.5),
level9 as(SELECT *
       ,SUM(flag_series) OVER (partition by customer_id order by order_date) as sum_flag_series
FROM level8),
level10 as(SELECT customer_id
       ,sum_flag_series
	   ,COUNT(sum_flag_series) as count_sum_flag_series
FROM level9
GROUP By customer_id, sum_flag_series),
level11 as(SELECT *
       ,count_sum_flag_series - 1 as real_count_sum_flag_series
FROM level10)
SELECT *
FROM level11
WHERE real_count_sum_flag_series >= 3

-- 417. «Клієнт з ефектом першого замовлення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id) as rn
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn = 1 THEN 'first_chek'
	   when rn >= 2 THEN 'next_chek'
	   END as cheks
FROM level1
WHERE count_order >= 5),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE cheks = 'first_chek')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE cheks = 'next_chek')::numeric,2) as avg_chek_next
FROM level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND((avg_chek_first / avg_chek_next)::numeric,2) as ratio
FROM level3)
SELECT *
FROm level4
WHERE ratio >= 1.5 OR ratio <= 0.5

-- 418. «Клієнт з ефектом середини історії»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2),0) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn < middle_point THEN 'beginn'
	   when rn = middle_point THEN 'middle'
	   when rn > middle_point THEN 'end'
	   END as gradation
FROM level1
WHERE count_order >= 9),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'beginn')::numeric,2) as avg_beginn_chek
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'middle')::numeric,2) as avg_middle_chek
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'end')::numeric,2) as avg_end_chek
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND(((avg_beginn_chek + avg_end_chek) / 2)::numeric,2) as avg_chek_between_beginn_and_end
FROm level3),
level5 as(SELECT *
       ,ROUND(ABS((avg_middle_chek - avg_chek_between_beginn_and_end) / avg_chek_between_beginn_and_end)::numeric,2) as diff
FROM level4)
SELECT *
FROM level5
WHERE diff >= 0.4

-- 419. «Клієнт із “пам’яттю знижки”»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROUND(AVG(discount)::numeric,2) as avg_discount
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn_early
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_late
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE rn_early <= 3)::numeric,2) as avg_chek_early
	   ,ROUND(AVG(sum_chek) FILTER (WHERE rn_late <= 3)::numeric,2) as avg_chek_late
	   ,ROUND(AVG(avg_discount) FILTER (WHERE rn_early <= 3)::numeric,2) as avg_discount_early
	   ,ROUND(AVG(avg_discount) FILTER (WHERE rn_late <= 3 )::numeric,2) as avg_discount_late
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,avg_discount_late - avg_discount_early as discount_swing
	   ,ROUND((avg_chek_late / avg_chek_early)::numeric,2) as chek_swing
FROM level3)
SELECT *
FROM level4
WHERE discount_swing >= 0.05 AND chek_swing >= 1.3

-- 420. «Клієнт з ефектом локального максимуму»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,LEAD(order_date) OVER (partition by customer_id order by order_date) as next_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ABS(order_date - prev_date) as prev_delta
	   ,ABS(order_date - next_date) as next_delta
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROM level1
WHERE count_order >=7),
level3 as(SELECT *
       ,case when sum_chek > prev_chek AND sum_chek > next_chek THEN 1 ELSE 0 END as flag_chek
	   ,(prev_delta + next_delta) / 2 as avg_delta
FROm level2),
level4 as(SELECT *
       ,case when flag_chek = 1 THEN order_date END as date_pick
FROM level3),
level5 as(SELECT *
FROm level4
WHERE date_pick is not null),
level6 as(SELECT *
       ,LAG(date_pick) OVER (partition by customer_id order by order_date) as prev_date_pick
	   ,COUNT(flag_chek) OVER (partition by customer_id) as count_flag_chek
FROM level5),
level7 as(SELECT *
       ,date_pick - prev_date_pick as pick_interval
FROm level6 
WHERE prev_date_pick is not null),
level8 as(SELECT *
       ,ROUND(AVG(pick_interval) OVER (partition by customer_id)::numeric,2) as avg_pick_interval
FROm level7)
SELECT *
FROm level8
WHERE count_flag_chek >= 2 AND avg_pick_interval <= 60

-- 421. «Клієнт із парадоксом стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn_first_3
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_last_3
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,ROUND(STDDEV(sum_chek) FILTER (WHERE rn_first_3 <= 3)::numeric,2) as std_dev_chek_first
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE rn_last_3 <= 3)::numeric,2)  as std_dev_chek_last
FROm level2
GROUP BY customer_id)
SELECT *
FROm level3
WHERE std_dev_chek_first > std_dev_chek_last