-- 588. «Клієнт з ефектом локального максимуму»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_quantity) OVER (partition by customer_id) as max_quantity
FROm level1
WHERE count_order >= 9),
level3 as(SELECT *
       ,MIN(case when sum_quantity = max_quantity THEN order_date END) OVER (partition by customer_id) as date_max_quantity
FROm level2),
level4 as(SELECT *
       ,case when order_date < date_max_quantity THEN '1_before'
	   when order_date > date_max_quantity THEN '2_after'
	   when order_date = date_max_quantity THEN 'equal'
	   END as gradation
FROm level3),
level5 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id, gradation order by order_date) as rn_after
	   ,ROW_NUMBER () OVER (partition by customer_id, gradation order by order_date DESC) as rn_before
FROM level4
WHERE gradation IN ('1_before', '2_after')),
level6 as(SELECT *
       ,COUNT(order_id) FILTER (WHERE gradation = '1_before') OVER (partition by customer_id) as count_order_before
	   ,COUNT(order_id) FILTER (WHERE gradation = '2_after') OVER (partition by customer_id) as count_order_after
FROm level5),
level7 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE gradation = '1_before' AND rn_before <= 3)::numeric,2) as avg_quantity_before
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE gradation = '2_after' AND rn_after <= 3)::numeric,2) as avg_quantity_after
FROm level6
WHERE count_order_before >= 3 AND count_order_after >= 3
GROUP By customer_id),
level8 as(SELECT *
       ,ROUND((avg_quantity_before / avg_quantity_after)::numeric,2) as ratio
FROM level7)
SELECT *
FROm level8
WHERE avg_quantity_after < avg_quantity_before AND ratio >= 1.2

-- 589. «Клієнт з ефектом зсуву норми»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
WHERE count_order >= 10),
level3 as(SELECt customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,case when sum_quantity > median_quantity THEN 1 ELSE 0 END as flag_quantity
FROM level2
JOIN level3 USING (customer_id)),
level5 as(SELECT customer_id
       ,COUNT(order_id) FILTER (WHERE halfs = 'first') as count_order_first
	   ,COUNT(order_id) FILTER (WHERE halfs = 'second') as count_order_second
	   ,sum(flag_quantity) FILTER (WHERE halfs = 'first') as sum_flag_quantity_first
	   ,sum(flag_quantity) FILTER (WHERE halfs = 'second') as sum_flag_quantity_second
FROM level4
GROUP BY customer_id),
level6 as(SELECT *
       ,ROUND((sum_flag_quantity_first::numeric / count_order_first::numeric),2) as ratio_first
	   ,ROUND((sum_flag_quantity_second::numeric / count_order_second::numeric),2) as ratio_second
FROm level5)
SELECT *
FROM level6
WHERE ratio_first <= 0.4 AND ratio_second >= 0.7

-- 590. «Клієнт з ефектом хибного відновлення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as (SELECT *
       ,MIN(sum_quantity) OVER (partition by customer_id) as min_quantity
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,MIN(case when sum_quantity = min_quantity THEN order_date END) OVER (partition by customer_id) as min_date_quantity
FROm level2),
level4 as(SELECT *
       ,case when order_date < min_date_quantity THEN '1_before'
	   when order_date > min_date_quantity THEN '2_after'
	   when order_date = min_date_quantity THEN 'equal'
	   END as gradation
FROm level3),
level5 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id, gradation order by order_date) as rn_after
	   ,ROW_NUMBER () OVER (partition by customer_id, gradation order by order_date DESC) as rn_before
FROm level4
WHERE gradation IN ('1_before', '2_after')),
level6 as(SELECT customer_id
       ,COUNT(order_id) FILTER (WHERE gradation = '1_before') as count_order_before
	   ,COUNT(order_id) FILTER (WHERE gradation = '2_after') as count_order_after
FROM level5
GROUP BY customer_id),
level7 as(SELECT *
FROM level5
JOIN level6 USING (customer_id)
WHERE count_order_before >= 3 AND count_order_after >= 3),
level8 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE gradation = '1_before' AND rn_before <= 3)::numeric,2) as avg_quantity_before
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE gradation = '2_after' AND rn_after <= 3)::numeric,2) as avg_quantity_after
FROM level7
GROUP By customer_id)
SELECT *
FROm level8
WHERE avg_quantity_after > avg_quantity_before * 0.7
AND avg_quantity_after < avg_quantity_before

-- 591. «Клієнт з ефектом втраченої памʼяті»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROm level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,halfs
	   ,ROUND(corr(sum_quantity, prev_quantity)::numeric,4) as corr_quantity
FROm level2
GROUP By customer_id, halfs),
level4 as(SELECT customer_id
       ,ROUND(AVG(corr_quantity) FILTER (WHERE halfs = 'first')::numeric,4) as corr_quantity_first
	   ,ROUND(AVG(corr_quantity) FILTER (WHERE halfs = 'second')::numeric,4) as corr_quantity_second
FROM level2
JOIN level3 USING (customer_id, halfs)
GROUP BY customer_id)
SELECT *
FROM level4
WHERE corr_quantity_first >= 0.4 AND corr_quantity_second <= 0

-- 592. «Клієнт з ефектом згладжування»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
WHERE count_order >= 9),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second')::numeric,2) as avg_quantity_second
	   ,ROUND(STDDEV(sum_quantity) FILTER (WHERE halfs = 'first')::numeric,2) as stddev_quantity_first
	   ,ROUND(STDDEV(sum_quantity) FILTER (WHERE halfs = 'second')::numeric,2) as stddev_quantity_second
FROm level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(ABS((avg_quantity_second - avg_quantity_first) / avg_quantity_first)::numeric,2) as diff_quantity
FROm level3)
SELECT *
FROM level4
WHERE stddev_quantity_second <= 0.6 * stddev_quantity_first AND diff_quantity <= 0.05

-- 593. «Клієнт з ефектом фальшивої різноманітності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,SUM(quantity) OVER (partition by customer_id, order_id) as sum_quantity
	   ,MAX(quantity) OVER (partition by customer_id, order_id) as max_quantity
FROm level1),
level3 as(SELECT DISTINCT customer_id
       ,order_id
	   ,sum_quantity
	   ,max_quantity
FROm level2),
level4 as(SELECT *
       ,ROUND((max_quantity::numeric / sum_quantity::numeric),2) as dominance_ratio
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM level3),
level5 as(SELECT *
       ,case when dominance_ratio >= 0.7 THEN 1 ELSE 0 END as flag_dominance
FROm level4
WHERE count_order >= 6),
level6 as(SELECT *
       ,SUM(flag_dominance) OVER (partition by customer_id) as sum_flag_dominance
FROm level5),
level7 as(SELECT *
       ,ROUND((sum_flag_dominance::numeric / count_order::numeric),2) as ratio
FROM level6)
SELECT *
FROm level7
WHERE ratio >= 0.5

-- 594. «Клієнт з ефектом прихованої надлишковості»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_quantity) OVER (partition by customer_id)::numeric,2) as stddev_quantity
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND((stddev_quantity / avg_quantity)::numeric,2) as cv
FROm level2),
level4 as(SELECT DISTINCT customer_id
       ,count_order
	   ,avg_quantity
	   ,avg_chek
	   ,stddev_quantity
	   ,cv
FROm level3),
level5 as(SELECT * 
       ,ntile(4) OVER (order by avg_quantity DESC) as ntile_quantity
	   ,ntile(4) OVER (order by avg_chek DESC) as ntile_chek
FROm level4)
SELECT *
FROm level5
WHERE ntile_quantity = 1 AND ntile_chek IN (2,3,4) AND cv <= 0.3

-- 595. «Клієнт з ефектом зсуву одиничної економіки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((sum_chek / sum_quantity)::numeric,2) as price_effect
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
       ,ROUND(AVG(price_effect) OVER (partition by customer_id)::numeric,2) as avg_price_effect
	   ,ROUND(STDDEV(price_effect) OVER (partition by customer_id)::numeric,2) as stddev_price_effect
FROM level2),
level4 as(SELECT DISTINCT customer_id
       ,count_order
	   ,avg_chek
	   ,avg_price_effect
	   ,stddev_price_effect
FROM level3),
level5 as(SELECT *
       ,ntile(2) OVER (order by avg_chek DESC) as ntile_chek
	   ,ntile(2) OVER (order by avg_price_effect DESC) as ntile_price_effect
FROM level4)
SELECT *
FROM level5
WHERE ntile_chek = 1 AND ntile_price_effect = 2 
AND stddev_price_effect <= 0.25 * avg_price_effect

-- 596. «Клієнт з ефектом фальшивої ефективності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
	   ,ROUND(SUM(sum_quantity) OVER (partition by customer_id)::numeric,2) as total_quantity
FROM level1
WHERE count_order >= 6),
level3 as(SELECT DISTINCT customer_id
       ,count_order
	   ,avg_chek
	   ,avg_quantity
	   ,total_quantity
FROM level2),
level4 as(SELECT *
       ,ntile(2) OVER (order by avg_chek DESC) as ntile_chek
	   ,ntile(2) OVER (order by avg_quantity DESC) as ntile_quantity
FROm level3)
SELECT *
FROM level4
WHERE ntile_chek = 1 AND ntile_quantity = 2