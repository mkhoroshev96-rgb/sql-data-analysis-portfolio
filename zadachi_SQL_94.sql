-- 608. «Клієнт, у якого зникає “нормальний” стан»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,ROUND(((sum_quantity - median_quantity) / median_quantity)::numeric,2) as diff_quantity
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 9),
level4 as(SELECT *
       ,case when diff_quantity between -0.1 AND 0.1 THEN 'normal_zone'
	   when diff_quantity > 0.1 THEN 'high'
	   when diff_quantity < -0.1 THEN 'low'
	   END as gradation
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM level3),
level5 as(SELECT *
       ,case when rn_invert <= 4 THEN 'last_k_order'
	   else 'other' END as groups
FROM level4),
level6 as(SELECT customer_id
       ,COUNT(order_id) FILTER (WHERE groups = 'other' AND gradation = 'normal_zone') as count_normal
FROm level5
GROUP By customer_id),
level7 as(SELECT *
FROm level5
JOIN level6 USING(customer_id)
WHERE count_normal >= 2),
level8 as(SELECT customer_id
       ,COUNT(order_id) FILTER (WHERE groups = 'last_k_order' AND gradation = 'high') as count_high_in_last
	   ,COUNT(order_id) FILTER (WHERE groups = 'last_k_order' AND gradation = 'low') as count_low_in_last
	   ,COUNT(order_id) FILTER (WHERE groups = 'last_k_order' AND gradation = 'normal_zone') as count_normal_in_last
FROm level7
GROUP BY customer_id)
SELECT *
FROM level7
JOIN level8 USING (customer_id)
WHERE count_high_in_last >= 1 
AND count_low_in_last >= 1
AND count_normal_in_last = 0

-- 609. «Клієнт із розірваним причинно-часовим зв’язком»

WITH level1 as (SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity,1) OVER (partition by customer_id order by order_date) as prev_1_quantity
	   ,LAG(sum_quantity,2) OVER (partition by customer_id order by order_date) as prev_2_quantity
FROm level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,ROUND(corr(prev_1_quantity, sum_chek)::numeric,4) as corr_prev_1_and_chek
	   ,ROUND(corr(prev_2_quantity, sum_chek)::numeric,4) as corr_prev_2_and_chek
FROm level2
GROUP By customer_id)
SELECT *
FROM level3
WHERE corr_prev_2_and_chek > corr_prev_1_and_chek AND corr_prev_2_and_chek > 0.5

-- 610. «Клієнт з перевернутою реакцією»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order 
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level1
GROUP By customer_id),
level3 as(SELECT *
       ,case when sum_quantity > median_quantity THEN 'high'
	   when sum_quantity <= median_quantity THEN 'low'
	   END as groups
FROm level1
JOIN level2 USING (customer_id)
WHERE count_order >= 9),
level4 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
	   ,LAG(groups) OVER (partition by customer_id order by order_date) as prev_groups
FROm level3),
level5 as(SELECT *
       ,case when sum_quantity > prev_quantity then 'up'
	   when sum_quantity < prev_quantity then 'down'
	   when sum_quantity = prev_quantity then 'equal'
	   END as gradation
FROm level4
WHERE prev_quantity is not null),
level6 as(SELECT *
       ,case when prev_groups = 'high' AND gradation = 'down' THEN 1 ELSE 0 END as flag_high_down
	   ,case when prev_groups = 'low' AND gradation = 'up' THEN 1 ELSE 0 END as flag_low_up
	   ,count_order - 1 as real_count_order
FROm level5),
level7 as(SELECT *
       ,sum(flag_high_down) OVER (partition by customer_id) as sum_flag_high_down
	   ,sum(flag_low_up) OVER (partition by customer_id) as sum_flag_low_up
FROM level6),
level8 as(SELECT *
       ,ROUND((sum_flag_high_down::numeric / real_count_order::numeric),2) as ratio_high_down
	   ,ROUND((sum_flag_low_up::numeric / real_count_order::numeric),2) as ratio_low_up
FROm level7)
SELECT *
FROm level8
WHERE ratio_high_down >= 0.6 AND ratio_low_up >= 0.6

-- 611. «Клієнт із ефектом передчасного насичення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,sum(quantity) as sum_quantity
	   ,ROUND(avg(unit_price)::numeric,2) as avg_price
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
	   ,LAG(avg_price) OVER (partition by customer_id order by order_date) as prev_avg_price
FROM level1
WHERE count_order >= 9),
level3 as(SELECT *
       ,sum_quantity - prev_quantity as delta_quantity
	   ,avg_price - prev_avg_price as delta_avg_price
FROM level2),
level4 as(SELECT *
       ,case when delta_quantity > 0 THEN 1 ELSE 0 END as flag_quantity
	   ,case when delta_avg_price <= 0 THEN 1 ELSE 0 END as flag_avg_price
	   ,count_order - 1 as real_count
FROm level3
WHERE prev_quantity is not null AND prev_avg_price is not null),
level5 as(SELECT *
       ,case when flag_quantity = 1 AND flag_avg_price = 1 THEN 1 
	   ELSE 0 END as total_flag
FROm level4),
level6 as(SELECT *
       ,SUM(total_flag) OVER (partition by customer_id) as sum_total_flag
FROm level5),
level7 as(SELECT *
       ,ROUND((sum_total_flag::numeric / real_count),2) as ratio_total_flag
FROm level6)
SELECT *
FROm level7
WHERE ratio_total_flag >= 0.6

-- 612. «Клієнт із зламом цінового патерну» (запит написаний чатіком)

WITH level1 as(SELECT customer_id
       ,order_id
       ,order_date
       ,SUM(unit_price * quantity) / SUM(quantity) AS avg_price
       ,COUNT(order_id) OVER (PARTITION BY customer_id) AS count_orders
FROM orders 
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date) AS rn
FROM level1
WHERE count_orders >= 7),
level3 AS (
   SELECT *
          ,(SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY l2b.avg_price)
            FROM level2 l2b
            WHERE l2b.customer_id = l2.customer_id
              AND l2b.rn < l2.rn) AS median_before
          ,(SELECT MIN(l2a.avg_price)
            FROM level2 l2a
            WHERE l2a.customer_id = l2.customer_id
              AND l2a.rn >= l2.rn) AS min_after
    FROM level2 l2)
SELECT *
FROM level3
WHERE median_before IS NOT NULL
  AND min_after > median_before;

