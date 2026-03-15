-- 603. «Клієнт із ефектом хибної стабільності»

WITH level1 as(SELECt customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
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
FROm level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second')::numeric,2) as avg_quantity_second
	   ,ROUND(AVG(avg_price) FILTER (WHERE halfs = 'first')::numeric,2) as avg_price_first
	   ,ROUND(AVG(avg_price) FILTER (WHERE halfs = 'second')::numeric,2) as avg_price_second
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
FROm level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,2) as diff_chek
FROm level3
WHERE avg_quantity_second > avg_quantity_first AND avg_price_second < avg_price_first)
SELECT *
FROM level4
WHERE diff_chek <= 0.05;

-- 604. «Клієнт, якого неможливо сегментувати»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,COUNT(DISTINCT product_id) as count_unik_product
FROm level1
GROUP By customer_id, order_id),
level3 as(SELECT *
       ,SUM(quantity) OVER (partition by customer_id, order_id) as sum_quantity
FROm level1
JOIN level2 USING (customer_id, order_id)),
level4 as(SELECT DISTINCT customer_id
       ,order_id
	   ,order_date
	   ,count_unik_product
	   ,sum_quantity
FROm level3),
level5 as(SELECT *
       ,ROUND((sum_quantity::numeric / count_unik_product::numeric),2) as order_profile
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm level4),
level6 as(SELECT *
FROM level5
WHERE count_order >= 10),
level7 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by order_profile) as median_order_profile
	   ,ROUND(AVG(order_profile)::numeric,2) as avg_order_profile
FROM level6
GROUP BY customer_id),
level8 as(SELECT *
       ,case when order_profile >= median_order_profile THEN 'high'
	   when order_profile < median_order_profile THEN 'low'
	   END as median_groups
FROM level6
JOIN level7 USING (customer_id)),
level9 as(SELECT *
       ,LEAD(median_groups) OVER (partition by customer_id order by order_date) as next_median_groups
FROM level8),
level10 as(SELECT *
       ,case when (median_groups = 'high' AND next_median_groups = 'low') OR (median_groups = 'low' AND next_median_groups = 'high') THEN 1
	   ELSE 0 END as flag_order_profile
	   ,count_order - 1 as real_count
	   ,ROUND(ABS((avg_order_profile - median_order_profile) / median_order_profile)::numeric,2) as diff_order_profile
FROm level9),
level11 as(SELECT *
       ,SUM(flag_order_profile) OVER (partition by customer_id) as sum_flag_order_profile
FROm level10),
level12 as(SELECT *
       ,ROUND((sum_flag_order_profile::numeric / real_count::numeric),2) as ratio
FROm level11)
SELECT *
FROm level12
WHERE ratio >= 0.7 AND diff_order_profile <= 0.1

-- 605. «Клієнт, який ламає причинність»

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
FROm level1
WHERE count_order >= 9),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROm level2
GROUP By customer_id),
level4 as(SELECT *
       ,case when sum_quantity <= median_quantity THEN 'normal'
	   when sum_quantity > median_quantity THEN 'peak'
	   end as median_groups
FROM level2
JOIN level3 USING (customer_id)),
level5 as(SELECT *
       ,case when median_groups = 'normal' THEN 1 ELSE 0 END as is_anchor
FROm level4),
level6 as(SELECT *
       ,SUM(is_anchor) OVER (partition by customer_id order by order_date) as anchor_id 
FROm level5),
level7 as(SELECT *
       ,MAX(case when median_groups = 'normal' THEN sum_chek END) OVER (partition by customer_id, anchor_id) as anchor_sum_chek
FROm level6),
level8 as(SELECT *
       ,case when median_groups = 'peak' AND sum_chek < anchor_sum_chek THEN 1 
	   ELSE 0 END as broken_casuality
FROm level7),
level9 as(SELECT *
       ,SUM(broken_casuality) OVER (partition by customer_id) as sum_broken_casuality
FROm level8),
level10 as(SELECT *
       ,ROUND((sum_broken_casuality::numeric / count_order::numeric),2) as ratio
FROm level9)
SELECT *
FROm level10
WHERE ratio >= 0.7

-- 606. «Клієнт з ефектом хибного покращення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,count(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
	   ,case when sum_quantity >= median_quantity THEN 'high'
	   when sum_quantity < median_quantity THEN 'low'
	   END as gradation
FROm level1
JOIn level2 USING (customer_id)
WHERE count_order >= 10),
level4 as(SELECT customer_id
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first' AND gradation = 'high')::numeric,2) as avg_chek_high_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first' AND gradation = 'low')::numeric,2) as avg_chek_low_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second' AND gradation = 'high')::numeric,2) as avg_chek_high_second
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second' AND gradation = 'low')::numeric,2) as avg_chek_low_second
FROm level3
GROUP By customer_id),
level5 as(SELECT *
FROm level4
WHERE avg_chek_high_first is not null AND avg_chek_low_first is not null
AND avg_chek_high_second is not null AND avg_chek_low_second is not null)
SELECT *
FROm level5
WHERE avg_chek_second > avg_chek_first AND avg_chek_low_first > avg_chek_low_second
AND avg_chek_high_first > avg_chek_high_second

-- 607. «Клієнт з ілюзією середнього»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont (0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level1
GROUP By customer_id),
level3 as(SELECT *
       ,case when sum_chek > median_chek THEN 'high'
	   when sum_chek < median_chek THEN 'low'
	   when sum_chek = median_chek THEN 'equal'
	   END as gradation_chek
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 9),
level4 as(SELECT customer_id
       ,COUNT(order_id) FILTER (WHERE gradation_chek = 'high') as count_order_high
	   ,COUNT(order_id) FILTER (WHERE gradation_chek = 'low') as count_order_low
FROm level3
GROUP BY customer_id),
level5 as(SELECT *
       ,ROUND((count_order_high::numeric / count_order::numeric),2) as ratio_high
	   ,ROUND((count_order_low::numeric / count_order::numeric),2) as ratio_low
FROm level3
JOIN level4 USING (customer_id)),
level6 as(SELECT *
FROm level5
WHERE ratio_high between 0.45 AND 0.5 
AND ratio_low between 0.45 AND 0.5),
level7 as (SELECT *
       ,ROUND(ABS((sum_chek - median_chek) / median_chek)::numeric,2) as diff_chek 
FROm level6),
level8 as(SELECT *
       ,case when diff_chek > 0.1 THEN 1 ELSE 0 END as flag_diff
FROm level7),
level9 as(SELECT *
       ,SUM(flag_diff) OVER (partition by customer_id) as sum_flag_diff
FROm level8)
SELECT *
FROm level9
WHERE count_order = sum_flag_diff