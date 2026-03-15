-- 734. «Клієнт із інверсією кумулятивного балансу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,ROUND((count_order * 0.5)::numeric,0) as first_50_perc_orders
	   ,ROUND((count_order * 0.75)::numeric,0) as first_75_perc_orders
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,SUM(sum_chek) FILTER (WHERE rn <= first_50_perc_orders) OVER (partition by customer_id) as sum_chek_first_50_perc_orders
	   ,SUM(sum_chek) FILTER (WHERE rn <= first_75_perc_orders) OVER (partition by customer_id) as sum_chek_first_75_perc_orders
FROM level2),
level4 as(SELECT DISTINCT customer_id
       ,count_order
	   ,total_revenue
	   ,first_50_perc_orders
	   ,first_75_perc_orders
	   ,sum_chek_first_50_perc_orders
	   ,sum_chek_first_75_perc_orders
	   ,ROUND((sum_chek_first_50_perc_orders / total_revenue)::numeric,4) as ratio_first_50_perc_orders
	   ,ROUND((sum_chek_first_75_perc_orders / total_revenue)::numeric,4) as ratio_first_75_perc_orders
FROM level3)
SELECT *
FROM level4
WHERE ratio_first_50_perc_orders < 0.3 AND ratio_first_75_perc_orders > 0.8

-- 735. «Клієнт із прихованою зміною домінування»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,category_id
	   ,quantity
	   ,ROUND((p.unit_price * quantity * (1-discount))::numeric,2) as chek
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)),
level2 as(SELECT DISTINCT customer_id
       ,category_id
	   ,SUM(quantity) OVER (partition by customer_id, category_id) as sum_quantity
	   ,SUM(chek) OVER (partition by customer_id, category_id) as sum_chek
FROM level1),
level3 as(SELECT *
       ,DENSE_RANK () OVER (partition by customer_id order by sum_quantity DESC) as rn_quantity
	   ,DENSE_RANK () OVER (partition by customer_id order by sum_chek DESC) as rn_chek
FROM level2),
level4 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM orders
GROUP By customer_id)
SELECT *
FROM level3
JOIN level4 USING (customer_id)
WHERE count_order >= 12 AND (rn_chek = 1 AND rn_quantity <> 1)

-- 736. «Клієнт із прихованим самоперекриттям»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= 3 THEN 'first_orders'
	   when rn_invert <= 3 THEN 'last_orders'
	   else 'other' end as gradation
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'first_orders') OVER (partition by customer_id)::numeric,2) as avg_chek_first_orders
	   ,MAX(sum_chek) FILTER (WHERE gradation = 'last_orders') OVER (partition by customer_id) as max_chek_last_orders
	   ,MIN(sum_chek) FILTER (WHERE gradation = 'last_orders') OVER (partition by customer_id) as min_chek_last_orders
FROM level2
WHERE gradation IN ('first_orders', 'last_orders')),
level4 as(SELECT DISTINCT customer_id
       ,count_order
	   ,avg_chek_first_orders
	   ,max_chek_last_orders
	   ,min_chek_last_orders
FROM level3)
SELECT *
FROM level4
WHERE avg_chek_first_orders < max_chek_last_orders AND avg_chek_first_orders > min_chek_last_orders

-- 737. «Клієнт із прихованою симетрією рангу»

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
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,abs(sum_chek - avg_chek) as abs_diff
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
FROm level2),
level4 as(SELECT *
       ,DENSE_RANK () OVER (partition by customer_id order by abs_diff DESC) as rn_abs_diff 
FROm level3),
level5 as(SELECT *
       ,MAX(case when sum_chek = max_chek THEN rn_abs_diff END) OVER (partition by customer_id) as rn_abs_diff_max_chek
	   ,MAX(case when sum_chek = min_chek THEN rn_abs_diff END) OVER (partition by customer_id) as rn_abs_diff_min_chek
FROm level4)
SELECT *
FROM level5
WHERE rn_abs_diff_max_chek = rn_abs_diff_min_chek

-- 738. «Клієнт із внутрішнім перетином розподілу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
	   ,AVG(sum_chek) as avg_chek
FROM level1
GROUP By customer_id),
level3 as(SELECT *
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 12),
level4 as(SELECT *
       ,case when sum_chek > median_chek AND sum_chek < avg_chek THEN 1 ELSE 0 END as flag_chek
FROM level3),
level5 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level4)
SELECT *
FROM level5
WHERE sum_flag_chek = 1 AND flag_chek = sum_flag_chek

-- 739. «Товар із хибною стабільністю клієнтів»

WITH block1 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
	   ,STDDEV(sum_chek) OVER (partition by customer_id) as stddev_chek
FROM level1),
level3 as(SELECT *
       ,stddev_chek / avg_chek as cv
FROM level2),
level4 as(SELECT DISTINCT customer_id
       ,avg_chek
	   ,stddev_chek
	   ,cv
FROM level3),
level5 as(SELECT *
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by cv) FROM level4) as median_cv
FROM level4)
SELECT *
FROM level5
WHERE cv < median_cv),
block2 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
FROM orders
JOIN order_details USING (order_id))
SELECT *
       ,SUM(quantity) OVER (partition by product_id) as total_quantity
FROm level1),
block3 as(SELECT *
       ,SUM(quantity) OVER (partition by product_id) as sum_quantity_product_customer_low_cv
FROM block1
JOIN block2 USING (customer_id)),
block4 as(SELECT *
       ,ROUND((sum_quantity_product_customer_low_cv::numeric / total_quantity::numeric),4) as ratio
FROM block3)
SELECT *
FROM block4
WHERE ratio >= 0.7

-- 740. «Товар із ілюзією зростання»

WITH level1 as(SELECT product_id
       ,order_date
	   ,quantity
	   ,COUNT(product_id) OVER (partition by product_id) as count_product
	   ,COUNT(product_id) OVER (partition by product_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by product_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1),
level3 as(SELECT *
       ,SUM(quantity) OVER (partition by product_id) as total_revenue
	   ,ROUND(AVG(quantity) FILTER (WHERE halfs = 'first') OVER (partition by product_id)::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(quantity) FILTER (WHERE halfs = 'second') OVER (partition by product_id)::numeric,2) as avg_quantity_second
fROM level2),
level4 as(SELECT DISTINCT product_id
       ,total_revenue
	   ,avg_quantity_first
	   ,avg_quantity_second
FROM level3),
level5 as(SELECT *
       ,NTILE(4) OVER (order by total_revenue) as ntile_revenue
FROM level4)
SELECT *
FROM level5
WHERE ntile_revenue = 1 AND avg_quantity_second >= 1.4 * avg_quantity_first

-- 741. «Клієнт із хибним центром маси»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
FROM level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,percentile_cont (0.5) WITHIN GROUP (order by sum_chek) as median_chek
	   ,AVG(sum_chek) as avg_chek
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,sum_chek / avg_chek as diff
FROM level2
JOIN level3 USING (customer_id)
WHERE avg_chek > median_chek),
level5 as(SELECT *
       ,case when diff > 2 THEN 1 else 0 END as flag_diff
FROm level4),
level6 as(SELECT *
       ,SUM(flag_diff) OVER (partition by customer_id) as sum_flag_diff
FROM level5)
SELECT *
FROM level6
WHERE sum_flag_diff = 0

-- 742. «Клієнт із прихованим зламом порядку»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn_date
	   ,ROW_NUMBER () OVER (partition by customer_id order by sum_chek DESC) as rn_chek
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,ROUND(AVG(rn_date) OVER (partition by customer_id)::numeric,2) as avg_rn_date
	   ,ROUND(AVG(rn_chek) OVER (partition by customer_id)::numeric,2) as avg_rn_chek
FROM level2)
SELECT *
FROM level3
WHERE avg_rn_date <> avg_rn_chek

-- 743. «Клієнт із чистим розшаруванням розподілу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
FROM level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level2
GROUP By customer_id),
level4 as(SELECT *
       ,ntile(2) OVER (partition by customer_id order by sum_chek DESC) as ntile_chek
FROm level2
JOIN level3 USING (customer_id)),
level5 as(SELECT *
       ,MIN(sum_chek) FILTER (WHERE ntile_chek = 1) OVER (partition by customer_id) as min_chek_ntile_1
FROM level4),
level6 as(SELECT *
        ,case when min_chek_ntile_1 > median_chek THEN 'yes'
		ELSE 'no' END as gradation
FROM level5)
SELECT *
FROM level6
WHERE gradation = 'yes'