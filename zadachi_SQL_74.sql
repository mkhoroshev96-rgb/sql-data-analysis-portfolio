-- 468. «Клієнт-інверсія»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
Group by customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,ROUND(AVG(count_order) OVER (partition by customer_id)::numeric,2) as counts
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND((total_revenue / counts)::numeric,2) as avg_revenue_per_order
FROM level2),
level4 as(SELECT *
       ,DENSE_RANK () OVER (order by counts DESC) as rank_counts
	   ,DENSE_RANK () OVER (order by avg_revenue_per_order) as rank_revenue_per_order
FROM level3),
level5 as(SELECT *
       ,ntile(5) OVER (partition by customer_id order by sum_chek DESC) as ntile_5
FROM level4
WHERE rank_counts <= 20 AND rank_revenue_per_order <= 20),
level6 as(SELECT *
       ,case when ntile_5 = 1 THEN 'top'
	   when ntile_5 >= 2 THEN 'other'
	   END as gradation
FROM level5),
level7 as (SELECT *
       ,count(*) FILTER (WHERE gradation = 'top') OVER (partition by customer_id) as count_top
FROM level6),
level8 as(SELECT *
       ,SUM(sum_chek) FILTER (WHERE ntile_5 = 1) OVER (partition by customer_id) as revenue_per_top
FROM level7),
level9 as(SELECT *
       ,ROUND((revenue_per_top / total_revenue)::numeric,2) as ratio
FROM level8)
SELECT *
FROM level9
WHERE ratio >= 0.5

-- 469. «Клієнт, який покращує середнє, але погіршує бізнес»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,SUM(sum_chek) as total_revenue
       ,ROUND(AVG(count_order)::numeric,2) as counts
FROM level1
WHERE count_order >= 5
GROUP BY customer_id),
level3 as(SELECT *
       ,ROUND((total_revenue / counts)::numeric,2) as avg_revenue_per_order
	   ,SUM(total_revenue) OVER () as global_revenue
FROM level2),
level4 as(SELECT *
       ,SUM(avg_revenue_per_order) OVER () as global_sum_avg_per_order
	   ,COUNT(*) OVER () as count_customers
FROM level3),
level5 as(SELECT *
       ,ROUND((global_revenue - total_revenue) / (count_customers - 1)::numeric,2) as revenue_ohne_customer
	   ,ROUND((global_sum_avg_per_order - avg_revenue_per_order) / (count_customers - 1)::numeric,2) as avg_revenue_ohne_customer
FROM level4)
SELECT *
FROM level5
WHERE avg_revenue_per_order > avg_revenue_ohne_customer and total_revenue < revenue_ohne_customer

-- 470. «Ефект зламаної памʼяті клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::Numeric,2) as chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_last
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn_last = 1 THEN 'last'
	   when rn_last >= 2 THEN 'other'
	   END as groups
FROM level1
WHERE count_order >= 5),
level3 as(SELECT customer_id
       ,groups
	   ,percentile_cont(0.5) WITHIN GROUP (order by chek) as median
	   ,ROUND(AVG(sum_quantity)::numeric,2) as avg_quantity
FROM level2
GROUP By customer_id, groups),
level4 as(SELECT *
       ,AVG(median) FILTER (where groups = 'other') OVER (partition by customer_id) as median_other
	   ,AVG(median) FILTER (where groups = 'last') OVER (partition by customer_id) as median_last
	   ,ROUND(AVG(avg_quantity) FILTER (where groups = 'other') OVER (partition by customer_id)::numeric,2) as avg_quantity_other
	   ,ROUND(AVG(avg_quantity) FILTER (where groups = 'last') OVER (partition by customer_id)::numeric,2) as avg_quantity_last 
FROM level2
JOIN level3 USING (customer_id, groups))
SELECT *
FROM level4
where median_last < median_other AND avg_quantity_last > avg_quantity_other

-- 471. «Клієнт-обманка»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,product_id
	   ,SUM(chek) as sum_chek_product
	   ,SUM(quantity) as sum_quantity_product
FROm level1
GROUP BY customer_id, product_id
ORDER BY customer_id, product_id),
level3 as(SELECT *
       ,SUM(sum_chek_product) OVER (partition by customer_id) as total_revenue
	   ,SUM(sum_quantity_product) OVER (partition by customer_id) as total_quantity
FROM level2),
level4 as(SELECT *
       ,ROUND((sum_chek_product / total_revenue)::Numeric,2) as ratio_chek
	   ,ROUND((sum_quantity_product / total_quantity)::numeric,2) as ratio_quantity
FROM level3),
level5 as(SELECT *
       ,MAX(ratio_quantity) OVER (partition by customer_id) as max_ratio_quantity
FROM level4)
SELECT *
FROM level5
WHERE max_ratio_quantity >= 0.9 AND max_ratio_quantity = ratio_quantity
AND ratio_chek <= 0.9

-- 472. «Ілюзія стабільного працівника»

WITH level1 as(SELECT employee_id
       ,order_id
       ,order_date
	   ,EXTRACT(month from order_date) as month
	   ,EXTRACT(year FROM order_date) as year
FROM orders
JOIN order_details USING (order_id)
JOIN products USING (product_id)
JOIN employees USING (employee_id)),
level2 as(SELECT employee_id
       ,month
	   ,year
	   ,count(order_id) as count_order
	   ,COUNT(month) OVER (partition by employee_id) as count_month
FROM level1
GROUP By employee_id,month, year
ORDER BY employee_id,year, month),
level3 as(SELECT *
       ,ROUND(STDDEV(count_order) OVER (partition by employee_id)::numeric,2) as std_dev_order_count
	   ,ROUND(AVG(count_order) OVER (partition by employee_id)::numeric,2) as avg_count_order
FROM level2
WHERE count_month >= 6),
level4 as(SELECT *
       ,ROUND((std_dev_order_count / avg_count_order)::numeric,2) as cv
FROM level3)
SELECT *
FROM level4
WHERE cv <= 0.25

-- 473. «Категорія-паразит»

WITH level1 as(SELECT category_id
       ,order_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by category_id) as count_order
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
GROUP BY category_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by category_id)::numeric,2) as avg_chek
	   ,ROUND((sum_chek / sum_quantity)::numeric,2) as profit_per_unit
FROM level1),
level3 as(SELECT *
       ,ROUND(avg(profit_per_unit) OVER (partition by category_id)::numeric,2) as avg_profit_per_unit
FROM level2),
level4 as(SELECT DISTINCT category_id
       ,count_order
	   ,avg_chek
	   ,avg_profit_per_unit
FROM level3),
level5 as(SELECT *
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by avg_chek) FROM level4) as median_chek
	   ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by avg_profit_per_unit) FROM level4) as median_profit
	   ,NTILE(4) OVER (order by count_order DESC) as top_25_count
FROM level4)
SELECT *
FROM level5
WHERE top_25_count = 1 AND avg_chek < median_chek AND avg_profit_per_unit < median_profit
