-- 766. «Клієнт із фантомною стабільністю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,AVG(freight) as avg_freight
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,avg_freight / sum_chek as shipping_share
FROM level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by shipping_share)::numeric,4) as median_shipping
FROM level2
GROUP BY customer_id)
SELECT *
FROM level3
ORDER BY median_shipping DESC
LIMIT 10

-- 767. «Індекс інерції клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1
WHERE count_order >= 18)
SELECT customer_id
       ,corr(sum_chek, prev_chek) as corr_chek_prev_chek
FROm level2
GROUP By customer_id

-- 768. «Товар із фінансовою залежністю»

WITH level1 as(SELECT customer_id
	   ,order_id
	   ,order_date
	   ,product_id
	   ,quantity
	   ,(unit_price * quantity * (1-discount)) as chek
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,SUM(chek) OVER (partition by product_id) as sum_chek_per_product
	   ,SUM(chek) OVER (partition by product_id, customer_id) as sum_chek_customer
	   ,SUM(quantity) OVER (partition by product_id) as sum_quantity
FROM level1),
level3 as(SELECT DISTINCT customer_id
       ,product_id
	   ,sum_chek_per_product
	   ,sum_chek_customer
	   ,sum_quantity
FROM level2
WHERE sum_quantity >= 200),
level4 as(SELECT *
       ,ROUND((sum_chek_customer::numeric / sum_chek_per_product::numeric),4) as ratio
FROM level3),
level5 as(SELECT *
       ,MAX(ratio) OVER (partition by product_id) as max_ratio
FROM level4),
level6 as(SELECT DISTINCT product_id
       ,customer_id
	   ,max_ratio
FROM level5
WHERE ratio = max_ratio)
SELECT *
FROM level6
ORDER BY max_ratio DESC
LIMIT 10

-- 769. «Клієнт із крихкою історією»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER(partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when next_chek > sum_chek THEN 0 ELSE 1 END as flag_chek
FROM level2
WHERE next_chek is not null),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id order by order_date) as series_id
FROM level3),
level5 as(SELECT customer_id
       ,series_id
	   ,COUNT(series_id) FILTER (WHERE flag_chek = 0) as langth_series
FROM level4
GROUP BY customer_id, series_id),
level6 as(SELECT *
FROM level4
JOIN level5 USING (customer_id, series_id))
SELECT DISTINCT customer_id
       ,series_id
	   ,langth_series
FROM level6
ORDER BY langth_series DESC
LIMIT 10

-- 770. «Товар з ілюзією стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,COUNT(product_id) OVER (partition by product_id) as count_product
FROM level1),
level3 as(SELECT *
       ,STDDEV(quantity) OVER (partition by product_id) as stddev_quantity
	   ,AVG(quantity) OVER (partition by product_id) as avg_quantity
FROm level2
WHERE count_product >= 40),
level4 as(SELECT *
       ,ROUND((stddev_quantity / avg_quantity),4) as cv_quantity
FROm level3)
SELECT DISTINCT product_id
       ,cv_quantity
FROm level4
ORDER BY cv_quantity 
LIMIT 10

-- 771. «Клієнт з інверсійною структурою кошика»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
FROM level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by avg_price)::numeric,2) as median_price
FROm level2
GROUP By customer_id),
level4 as(SELECT *
       ,case when avg_price > median_price THEN 'price_high_median'
	   else 'other' END as group_price
FROM level2
JOIN level3 USING (customer_id)),
level5 as(SELECT *
       ,COUNT(order_id) FILTER (WHERE group_price = 'price_high_median') Over (partition by customer_id) as count_order_high_median
FROM level4),
level6 as(SELECT *
       ,ROUND((count_order_high_median::numeric / count_order::numeric),4) as ratio 
FROM level5)
SELECT DISTINCT customer_id
       ,count_order
	   ,count_order_high_median
	   ,ratio
FROm level6
ORDER BY ratio DESC
LIMIT 10

-- 772. «Товар з ефектом прихованого зсуву часу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,COUNT(product_id) OVER (partition by product_id) as count_product
FROM level1),
level3 as(SELECT *
       ,EXTRACT(EPOCH from order_date::timestamp)/86400 as order_date_in_days
FROm level2
WHERE count_product >= 40),
level4 as(SELECT product_id
       ,percentile_cont(0.5) WITHIN GROUP (order by order_date_in_days) as median_order_date_in_days
	   ,AVG(order_date_in_days) as avg_order_date_in_days
FROM level3
GROUP BY product_id)
SELECT *
       ,ABS(median_order_date_in_days - avg_order_date_in_days) as abs_shift
FROM level4
ORDER BY abs_shift DESC
LIMIT 10

-- 773. «Клієнт з ефектом структурної декомпозиції»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,(unit_price * quantity * (1-discount)) as chek
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,SUM(chek) OVER (partition by customer_id, order_id) as sum_order_chek
	   ,AVG(chek) OVER (partition by customer_id, order_id) as avg_chek_per_order
FROM level1),
level3 as(SELECT DISTINCT customer_id
       ,order_id
	   ,order_date
	   ,sum_order_chek
	   ,avg_chek_per_order
FROM level2),
level4 as(SELECT *
       ,AVG(sum_order_chek) OVER (partition by customer_id) as avg_chek
	   ,AVG(avg_chek_per_order) OVER (partition by customer_id) as avg_chek_per_order_customer
FROM level3),
level5 as(SELECT DISTINCT customer_id
       ,avg_chek
	   ,avg_chek_per_order_customer
FROM level4),
level6 as(SELECT *
       ,ABS(avg_chek - avg_chek_per_order_customer) as abs_diff_avg_chek
FROM level5
ORDER BY abs_diff_avg_chek DESC),
level7 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM orders
GROUP BY customer_id)
SELECT *
FROM level6
JOIN level7 USING (customer_id)
WHERE count_order >= 7
LIMIT 10