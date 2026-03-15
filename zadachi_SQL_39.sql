-- 242. “Клієнти з нестабільною структурою замовлень”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders 
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as count_order
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROM level1),
level3 as(SELECT *
       ,ROUND(((sum_chek::numeric / total_revenue::numeric)*100),2) as ratio
FROM level2
where count_order >= 3),
level4 as(SELECt *
       ,ROW_NUMBER() OVER (partition by customer_id order by ratio DESC) as rn_ratio
FROM level3)
SELECT *
FROM level4
WHERE rn_ratio = 1 AND ratio > 50 

-- 243. “Клієнти з ілюзією стабільності”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as count_order
FROM level1),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek)::numeric,2) as std_dev_chek
FROM level2
where count_order >= 5
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND((std_dev_chek::numeric / avg_chek::numeric),2) as coef_var
FROM level3),
level5 as(SELECT customer_id
       ,avg_chek
	   ,coef_var
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by avg_chek) FROM level4) as median_avg_chek
	   ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by coef_var) FROM level4) as median_coef_var
FROM level4
GROUP BY customer_id, avg_chek,coef_var),
level6 as(SELECT *
       ,ROUND((avg_chek/median_avg_chek)::numeric,2) as ratio_avg_chek
FROM level5),
level7 as(SELECT *
       ,case when ratio_avg_chek >= 0.9 AND ratio_avg_chek <= 1.1 THEN 'yes'
	   ELSE 'no' END as gradation
FROm level6)
SELECT *
FROM level7 
WHERE gradation = 'yes' AND coef_var > median_coef_var

-- 244. “Клієнти з ефектом хибного зростання”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
FROM orders
JOIn order_details USING(order_id)
GROUP BY customer_id,order_id,order_date),
level2 as(SELECT *
       ,COUNT(*) over(partition by customer_id) as count_order
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_sum_chek
	   ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_sum_quantity
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > prev_sum_chek THEN 1 ELSE 0 END as flag_chek
	   ,case when sum_quantity <= prev_sum_quantity THEN 1 ELSE 0 END as flag_quantity
	   ,count_order - 1 as real_count_order
FROM level2
WHERE count_order >= 6),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
	   ,SUM(flag_quantity) OVER (partition by customer_id) as sum_flag_quantity
FROM level3)
SELECT *
FROm level4
WHERE real_count_order = sum_flag_chek AND real_count_order = sum_flag_quantity

-- 245. “Клієнти з прихованою інфляцією”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price * (1-discount))::numeric,2) as avg_price_after_discount
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as count_order
	   ,LAG(avg_price_after_discount) OVER (partition by customer_id order by order_date) as prev_avg_price
	   ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_sum_quantity
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_sum_chek
FROM level1),
level3 as(SELECT *
       ,case when avg_price_after_discount > prev_avg_price THEN 1 ELSE 0 END as flag_price
	   ,case when sum_quantity < prev_sum_quantity THEN 1 ELSE 0 END as flag_quantity
	   ,case when sum_chek <= prev_sum_chek THEN 1 ELSE 0 END as flag_chek
FROM level2
WHERE count_order >= 6),
level4 as(SELECT *
       ,count_order - 1 as real_count_order
	   ,SUM(flag_price) OVER (partition by customer_id) as sum_flag_price
	   ,SUM(flag_quantity) OVER (partition by customer_id) as sum_flag_quantity
	   ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROm level3
where prev_avg_price is not null)
SELECT *
FROM level4
WHERE sum_flag_price = real_count_order 
AND sum_flag_quantity = real_count_order 
AND sum_flag_chek = real_count_order

-- 246. “Працівники з перекошеною географією доставки”

WITh level1 as(SELECT employee_id
       ,order_id
	   ,ship_country
	   ,order_date
	   ,shipped_date
	   ,shipped_date - order_date as interval
FROM orders
JOIN employees USING (employee_id)),
level2 as(SELECT *
       ,COUNT(*) OVER (partition by employee_id, ship_country) as count_ship_country
       ,COUNT(*) OVER (partition by employee_id) as count_order
	   ,ROUND(AVG(interval) OVER (partition by employee_id, ship_country)::numeric,2) as avg_interval
FROm level1),
level3 as(SELECT *
       ,ROUND(((count_ship_country::numeric / count_order::numeric)*100),2) as ratio_per_ship_country
FROm level2
WHERE count_order > 20),
level4 as(SELECT DISTINCT employee_id ,ship_country
       ,avg_interval
	   ,ratio_per_ship_country
	   ,DENSE_RANK() OVER (partition by employee_id order by ratio_per_ship_country DESC) as rank_ratio
FROM level3
ORDER BY employee_id, rank_ratio),
level5 as(SELECT *
       ,case when rank_ratio = 1 THEN 'top'
	   else 'other' END as gradation
FROM level4),
level6 as(SELECT employee_id
       ,ROUND(AVG(avg_interval) FILTER (WHERE gradation = 'top')::numeric,2) as avg_interval_per_top
	   ,ROUND(AVG(avg_interval)::numeric,2) as avg_interval_per_employee
FROm level5
GROUP By employee_id),
level7 as(SELECT *
FROM level5
JOIN level6 USING(employee_id)),
level8 as(SELECT *
FROm level7
where avg_interval_per_top > avg_interval_per_employee)
SELECT *
FROm level8
WHERE rank_ratio = 1 AND ratio_per_ship_country >= 60

-- 247. “Категорії з прихованою залежністю від постачальника”

WITH level1 as(SELECT category_id
       ,supplier_id
	   ,product_id
	   ,ROUND(AVG(p.unit_price) OVER (partition by category_id)::numeric,2) as avg_price_per_category
	   ,ROUND(AVG(p.unit_price) OVER (partition by category_id, supplier_id)::numeric,2) as avg_price_per_supplier
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(*) OVER (partition by category_id) as count_product
FROm orders
JOIn order_details USING(order_id)
JOIN products p USING(product_id)
JOIN categories USING(category_id)
JOIN suppliers USING(supplier_id)
GROUP BY category_id, supplier_id, product_id, p.unit_price),
level2 as(SELECT DISTINCT category_id,supplier_id
       ,avg_price_per_category
	   ,avg_price_per_supplier
	   ,SUM(sum_chek) OVER (partition by category_id, supplier_id) as sum_revenue_per_supplier
	   ,SUM(sum_chek) OVER (partition by category_id) as total_revenue
FROm level1
where count_product >= 10
ORDER by category_id, supplier_id),
level3 as(SELECT *
       ,ROUND(((sum_revenue_per_supplier::numeric / total_revenue::numeric)*100),2) as ratio
FROM level2),
level4 as(SELECT *
       ,DENSE_RANK () OVER (partition by category_id order by ratio DESC) as rank_ratio
FROm level3)
SELECT *
FROM level4
WHERE rank_ratio = 1 AND  ratio >= 50 AND avg_price_per_supplier > avg_price_per_category

