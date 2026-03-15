-- 483. «Клієнт з хибною стабільністю»

WITH block1 as(WITH level1 as (SELECT customer_id
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
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 6),
level4 as(SELECT *
       ,case when sum_chek > median_chek THEN 'high'
	   when sum_chek < median_chek THEN 'low'
	   when sum_chek = median_chek THEN 'normal'
	   END as gradation
FROM level3),
level5 as(SELECT *
       ,LAG(gradation) OVER (partition by customer_id order by order_date) as prev_gradation
FROM level4),
level6 as(SELECT *
       ,case when (gradation = 'high' AND prev_gradation = 'low') OR (gradation = 'low' AND prev_gradation = 'high') THEN 1
	   ELSE 0 END as flag_grad
FROM level5)
SELECT *
       ,sum(flag_grad) OVER (partition by customer_id) as sum_flag_grad
FROM level6),
block2 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1),
level3 as(SELECT * 
       ,ROUND((ABS(avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_chek
FROM level2)
SELECT DISTINCT customer_id
       ,avg_chek
	   ,global_avg_chek
	   ,diff_chek
FROM level3)
SELECT *
FROM block1
JOIN block2 USING (customer_id)
WHERE sum_flag_grad >= 3 AND diff_chek < 0.05

-- 484. «Клієнт з ефектом зламаної пам’яті»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(discount)::numeric,4) as avg_discount
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by avg_discount)::numeric,4) as median_discount
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when avg_discount > median_discount THEN 'high'
	   when avg_discount < median_discount THEN 'low'
	   when avg_discount = median_discount THEN 'normal'
	   END as gradation
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 6),
level4 as(SELECT *
       ,LEAD(gradation) OVER (partition by customer_id order by order_date) as next_gradation
FROM level3),
level5 as(SELECT *
       ,LEAD(next_gradation) OVER (partition by customer_id order by order_date) as next_2_gradation
FROM level4),
level6 as(SELECT *
       ,case when gradation = 'high' AND next_gradation = 'low' AND next_2_gradation = 'low' THEN 1 
	   ELSE 0 END as flag_gradation
FROm level5),
level7 as(SELECT *
       ,SUM(flag_gradation) OVER (partition by customer_id) as sum_flag_gradation
FROm level6)
SELECT *
FROM level7
WHERE sum_flag_gradation >= 2

-- 485. «Клієнт з ілюзією росту»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,MAX(discount) as max_discount
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2),2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
	   ,case when max_discount > 0 THEN 1 ELSE 0 END as flag_discount
FROM level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second')::numeric,2) as avg_quantity_second
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,SUM(flag_discount) FILTER (WHERE halfs = 'first') as sum_flag_first
	   ,SUM(flag_discount) FILTER (WHERE halfs = 'second') as sum_flag_second
	   ,COUNT(order_id) FILTER (WHERE halfs = 'first') as count_order_first
	   ,COUNT(order_id) FILTER (WHERE halfs = 'second') as count_order_second
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND((sum_flag_first::numeric / count_order_first::numeric),2) as ratio_first
	   ,ROUND((sum_flag_second::numeric / count_order_second::numeric),2) as ratio_second
FROM level3)
SELECT *
FROM level4
WHERE avg_quantity_second > avg_quantity_first
AND avg_chek_second <= avg_chek_first
AND ratio_second > ratio_first

-- 486. «Клієнт з ефектом помилкового відновлення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,MAX(discount) as max_discount
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
	   ,case when max_discount > 0 THEN 1 ELSE 0 END as flag_discount
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,MIN(case when sum_chek = min_chek THEN order_date END) OVER (partition by customer_id) as date_break
FROM level2),
level4 as(SELECT *
       ,case when order_date < date_break THEN '1_before'
	   when order_date > date_break THEN '2_after'
	   when order_date = date_break THEN 'break'
	   END as groups
FROM level3),
level5 as(SELECT *
FROM level4
WHERE groups IN ('1_before','2_after')),
level6 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE groups = '1_before')::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE groups = '2_after')::numeric,2) as avg_chek_after
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE groups = '1_before')::numeric,2) as avg_quantity_before
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE groups = '2_after')::numeric,2) as avg_quantity_after
	   ,SUM(flag_discount) FILTER (WHERE groups = '1_before') as sum_flag_before
	   ,SUM(flag_discount) FILTER (WHERE groups = '2_after') as sum_flag_after
	   ,COUNT(order_id) FILTER (WHERE groups = '1_before') as count_order_before
	   ,COUNT(order_id) FILTER (WHERE groups = '2_after') as count_order_after
FROM level5
GROUP BY customer_id),
level7 as(SELECT *
       ,ROUND((sum_flag_before::numeric / count_order_before),2) as ratio_before
	   ,ROUND((sum_flag_after::numeric / count_order_after),2) as ratio_after
FROm level6
WHERE avg_chek_before is not null AND avg_chek_after is not null)
SELECT *
FROM level7
WHERE avg_chek_after > avg_chek_before AND avg_quantity_after <= avg_quantity_before
AND ratio_after > ratio_before

-- 487. «Клієнт із зниклим ефектом масштабу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECt *
       ,ROUND((sum_chek / sum_quantity),2) as avg_price_item
	   ,MAX(sum_quantity) OVER (partition by customer_id) as max_quantity
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when sum_quantity = max_quantity THEN 'max_order'
	   ELSE 'other' END as gradation 
FROM level2),
level4 as(SELECT customer_id
       ,ROUND(corr(sum_quantity, avg_price_item)::numeric,2) as corr_qnt_price
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
FROM level3
JOIN level4 USING (customer_id)
WHERE corr_qnt_price < 0),
level6 as(SELECT customer_id
       ,ROUND(corr(sum_quantity, avg_price_item) FILTER (WHERE gradation = 'other')::numeric,2) as corr_ohne_max_order
FROM level5
GROUP BY customer_id)
SELECT *
FROM level5
JOIN level6 USING (customer_id)
WHERE corr_ohne_max_order > 0

-- 488. «Клієнт з ефектом локального максимуму»

with level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,MAX(discount) as max_discount 
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
	   ,case when max_discount > 0 THEN 1 ELSE 0 END as flag_discount
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,case when sum_chek > prev_chek AND sum_chek > next_chek THEN 1 
	   ELSE 0 END as flag_chek 
FROM level2),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE flag_chek = 1)::numeric,2) as avg_chek_high
	   ,ROUND(AVG(sum_chek) FILTER (WHERE flag_chek = 0)::numeric,2) as avg_chek_low
	   ,SUM(flag_discount) FILTER (WHERE flag_chek = 1) as sum_flag_discount_high
	   ,SUM(flag_discount) FILTER (WHERE flag_chek = 0) as sum_flag_discount_low
	   ,COUNT(order_id) FILTER (WHERE flag_chek = 1) as count_order_high
	   ,COUNT(order_id) FILTER (WHERE flag_chek = 0) as count_order_low
FROm level3
GROUP BY customer_id),
level5 as(SELECT *
       ,ROUND((sum_flag_discount_high::numeric / count_order_high::numeric),2) as ratio_high
	   ,ROUND((sum_flag_discount_low::numeric / count_order_low::numeric),2) as ratio_low
FROM level4
WHERE avg_chek_high is not null AND avg_chek_low is not null)
SELECT *
FROM level5
WHERE avg_chek_high > avg_chek_low AND ratio_high > ratio_low

-- 489. «Клієнт з ефектом хибного прискорення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_last
FROM level1
WHERE count_order >= 5),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by interval) as median
FROM level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(AVG(interval) FILTER (WHERE rn_last = 1) OVER (partition by customer_id)::numeric,2) as interval_last
	   ,ROUND(AVG(sum_chek) FILTER (WHERE rn_last = 1) OVER (partition by customer_id)::numeric,2) as chek_last
FROM level2
JOIN level3 USING (customer_id))
SELECT *
FROM level4
WHERE interval_last < median AND chek_last < avg_chek