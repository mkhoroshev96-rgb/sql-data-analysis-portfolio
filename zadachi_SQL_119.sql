-- 798. «Індекс крихкості постачальника»

WITH level1 as(SELECT supplier_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,(p.unit_price * quantity * (1-discount)) as chek
FROm orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN suppliers s USING (supplier_id)),
level2 as(SELECT *
       ,SUM(chek) OVER (partition by supplier_id) as total_revenue
	   ,SUM(chek) OVER (partition by supplier_id, product_id) as revenue_suppliers_product
FROm level1),
level3 as(SELECT DISTINCT supplier_id
       ,product_id
	   ,revenue_suppliers_product
	   ,total_revenue
	   ,revenue_suppliers_product / total_revenue as ratio
FROM level2
ORDER BY supplier_id),
level4 as(SELECT *
       ,MAX(ratio) OVER (partition by supplier_id) as max_ratio  
FROm level3)
SELECT *
FROM level4
WHERE ratio = max_ratio
ORDER BY max_ratio DESC

-- 799. «Індекс фантомної стабільності клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,STDDEV(sum_chek) OVER (partition by customer_id) as stddev_chek
	   ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,stddev_chek / avg_chek as cv
FROm level2)
SELECT DISTINCT customer_id
       ,stddev_chek
	   ,avg_chek
	   ,cv
FROm level3
ORDER BY cv DESC

-- 800. «Клієнт із зламаною пам’яттю»

WITH level1 aS(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(select *
froM level1
WHERE count_order >= 12),
level3 as(SELECT a.customer_id
       ,a.sum_chek as chek_a
	   ,b.sum_chek as chek_b
FROm level2 a
JOIN level2 b ON a.customer_id = b.customer_id
AND a.rn = abs(b.rn - b.count_order) + 1),
level4 as(SELECT *
       ,abs(chek_a - chek_b) as abs_diff
FROm level3),
level5 as(SELECT *
       ,AVG(abs_diff) OVER (partition by customer_id) as avg_abs_diff
FROM level4)
SELECT DISTINCT customer_id
       ,avg_abs_diff
FROM level5
ORDER BY avg_abs_diff DESC

-- 801. «Товар з ілюзією зростання»

WITH level1 as(SELECT product_id
       ,order_id
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
level3 as(SELECT product_id
       ,AVG(quantity) FILTER (WHERE halfs = 'first') as avg_quantity_first
	   ,AVG(quantity) FILTER (WHERE halfs = 'second') as avg_quantity_second
	   ,SUM(quantity) FILTER (WHERE halfs = 'first') as total_quantity_first
	   ,SUM(quantity) FILTER (WHERE halfs = 'second') as total_quantity_second
FROM level2
GROUP By product_id),
level4 as(SELECT *
       ,avg_quantity_second - avg_quantity_first as illusion_index
FROM level3
WHERE total_quantity_second < total_quantity_first)
SELECT *
FROM level4
WHERE illusion_index > 0

-- 802. «Клієнт із парадоксом стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) OVER (partition by customer_id, order_id) as order_chek
	   ,COUNT(product_id) OVER (partition by customer_id, order_id) as count_product
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT DISTINCT customer_id
       ,order_id
	   ,order_date
	   ,order_chek
	   ,count_product
FROM level1),
level3 as(SELECT *
       ,AVG(order_chek) OVER (partition by customer_id) as avg_chek
	   ,STDDEV(order_chek) OVER (partition by customer_id) as stddev_chek
	   ,AVG(count_product) OVER (partition by customer_id) as avg_count_product
	   ,STDDEV(count_product) OVER (partition by customer_id) as stddev_count_product
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm level2),
level4 as(SELECT DISTINCT customer_id
       ,avg_chek
	   ,stddev_chek
	   ,avg_count_product
	   ,stddev_count_product
	   ,count_order
	   ,stddev_chek / avg_chek as cv_chek
	   ,stddev_count_product / avg_count_product as cv_count_product
FROM level3)
SELECT *
FROm level4
WHERE cv_chek < 0.15 AND cv_count_product > 0.6

-- 803. «Клієнт з фальшивим максимумом»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
FROm level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
	   ,MAX(sum_chek) as max_chek
FROm level2
GROUP By customer_id),
level4 as(SELECT *
       ,max_chek - median_chek as fare_max_index
FROm level3)
SELECT *
FROm level4
WHERE fare_max_index <= median_chek * 0.1

-- 804. «Клієнт, у якого максимум ніколи не був максимумом»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by sum_chek DESC) as rn_chek
FROM level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,MAX(sum_chek) FILTER (WHERE rn_chek = 1) as first_max_chek
	   ,MAX(sum_chek) FILTER (WHERE rn_chek = 2) as second_max_chek
FROM level2
WHERE rn_chek <= 2
GROUP By customer_id )
SELECT *
       ,first_max_chek - second_max_chek as fake_peak_index
FROM level3
ORDER BY fake_peak_index DESC

-- 805. «Клієнт із прихованим переломом поведінки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id order by order_date) as cumm_sum_chek
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,SUM(sum_chek) OVER (partition by customer_id) * 0.5 as half_total_revenue
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,ABS(half_total_revenue - cumm_sum_chek) as abs_diff
FROM level2),
level4 as(SELECT *
       ,MIN(abs_diff) OVER (partition by customer_id) as min_abs_diff
FROm level3),
level5 as(SELECT *
       ,MIN(case when abs_diff = min_abs_diff THEN order_date END) OVER (partition by customer_id) as date_break
FROM level4),
level6 as(SELECT *
       ,case when order_date < date_break THEN '1_before'
	   when order_date > date_break THEN '2_after'
	   when order_date = date_break THEN 'break'
	   END as groups
FROM level5),
level7 as(SELECT customer_id
       ,MAX(sum_chek) FILTER (WHERE groups = '1_before') as max_chek_before
	   ,MIN(sum_chek) FILTER (WHERE groups = '2_after') as min_chek_after
FROM level6
GROUP By customer_id)
SELECT *
       ,min_chek_after - max_chek_before as break_index
FROM level7
ORDER BY break_index DESC

-- 806. «Клієнт з ілюзією стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROm level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,case when sum_chek >= prev_chek THEN 0 ELSE 1 END as flag_chek
FROM level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id order by order_date) as series_id 
FROm level3),
level5 as(SELECT customer_id
       ,series_id
	   ,COUNT(series_id) FILTER (WHERE flag_chek = 0) as length_series
FROM level4
GROUP By customer_id, series_id
ORDER BY length_series DESC)
SELECT *
FROM level5
WHERE length_series >= 1

-- 807. Retention клієнтів (повернення після першого замовлення)

WITH level1 as(SELECT customer_id
	   ,COUNT(order_id) as count_order
FROM orders
GROUP BY customer_id),
level2 as(SELECT *
       ,case when count_order >= 2 THEN 'orders_2_plus'
	   else 'other' END as gradation
	   ,COUNT(customer_id) OVER () as total_customer
FROm level1),
level3 as(SELECT *
       ,COUNT(customer_id) FILTER (WHERE gradation = 'orders_2_plus') OVER () as count_customer_2_plus_order
FROm level2)
SELECT *
       ,count_customer_2_plus_order::numeric / total_customer::numeric as retention_ratio
FROm level3