-- 711. «Клієнт із дзеркальною структурою покупок» -- тепер я спробую сам її виршіити

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek 
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date, order_id) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC, order_id DESC) as rn_invert
FROM level1
WHERE count_order >= 10),
level3 as(SELECT a.customer_id
       ,a.sum_chek as chek_rn
	   ,a.count_order
	   ,a.rn
	   ,b.sum_chek as chek_rn_invert
	   ,b.rn_invert
FROM level2 a
JOIN level2 b ON a.customer_id = b.customer_id AND a.rn = b.rn_invert),
level4 as(SELECT *
       ,ROUND(ABS((chek_rn_invert - chek_rn) / chek_rn)::numeric,2) as diff_cheks
FROM level3),
level5 as(SELECT *
       ,case when diff_cheks <= 0.05 THEN 1 ELSE 0 END as flag_diff_cheks
FROm level4),
level6 as(SELECT * 
       ,SUM(flag_diff_cheks) OVER (partition by customer_id) as sum_flag_diff_cheks
FROM level5)
SELECT *
FROM level6
WHERE count_order = sum_flag_diff_cheks

-- 712. Знайди товари, для яких більше 80% загального проданого обсягу (quantity) припадає на одного-єдиного клієнта.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,product_id
	   ,SUM(quantity) as sum_quantity_prod_per_cust
FROm level1
GROUP By customer_id, product_id),
level3 as(SELECT product_id
       ,SUM(quantity) as total_quantity
FROm orders
JOIN order_details USING (order_id)
GROUP BY product_id),
level4 as(SELECT *
       ,ROUND((sum_quantity_prod_per_cust::numeric / total_quantity::numeric),4) as ratio
FROM level2
JOIN level3 USING (product_id))
SELECT *
FROm level4
WHERE ratio >= 0.8

-- 713. «Товар із фальшивою стабільністю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,ROUND(STDDEV(quantity) OVER (partition by product_id)::numeric,4) as stddev_product
FROM level1),
level3 as(SELECT product_id
       ,SUM(quantity) as sum_quantity
FROM level2
GROUP By product_id),
level4 as(SELECT DISTINCT product_id
       ,stddev_product
	   ,sum_quantity
FROM level2
JOIN level3 USING (product_id)),
level5 as(SELECT *
       ,NTILE(4) OVER (order by sum_quantity DESC) as ntile_quantity
	   ,NTILE(4) OVER (order by stddev_product) as ntile_stddev
FROM level4)
SELECT *
FROm level5
WHERE ntile_quantity = 1 AND ntile_stddev = 1

-- 714. «Товар із прихованою концентрацією в часі»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,EXTRACT (year from order_date) as year
	   ,product_id
	   ,quantity
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,SUM(quantity) OVER (partition by product_id, year) as sum_quantity_per_year
	   ,SUM(quantity) OVER (partition by product_id) as total_quantity
FROm level1),
level3 as(SELECT DISTINCT product_id
       ,year
	   ,sum_quantity_per_year
	   ,total_quantity
	   ,ROUND((sum_quantity_per_year::numeric / total_quantity::numeric),4) as ratio
FROM level2)
SELECT *
FROM level3
WHERE ratio >= 0.6

-- 715. «Товар із ілюзією різноманіття»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT product_id
       ,COUNT(DISTINCT customer_id) as count_unik_customer
FROM level1
GROUP By product_id),
level3 as(SELECT *
       ,ntile(4) OVER (order by count_unik_customer DESC) as ntile_count_customer
FROm level2),
level4 as(SELECT *
FROm level1
JOIN level3 USING (product_id)
WHERE ntile_count_customer = 1),
level5 as(SELECT product_id
       ,customer_id
	   ,SUM(quantity) as sum_quantity
FROM level4
GROUP By product_id, customer_id),
level6 as(SELECT *
       ,ntile(5) OVER (partition by product_id order by sum_quantity DESC) as ntile_top
	   ,SUM(sum_quantity) OVER (partition by product_id) as total_quantity
FROm level5),
level7 as(SELECT *
       ,SUM(sum_quantity) FILTER (where ntile_top = 1) OVER (partition by product_id) as sum_quantity_top
FROM level6),
level8 as(SELECT *
       ,ROUND((sum_quantity_top::numeric / total_quantity::numeric),4) as ratio
FROM level7)
SELECT *
FROm level8
WHERE ratio >= 0.7

-- 716. «Товар із “зворотною лояльністю”»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,product_id
	   ,SUM(quantity) as sum_quantity
FROM level1
GROUP BY customer_id, product_id),
level3 as(SELECT *
       ,DENSE_RANK () OVER (partition by customer_id order by sum_quantity DESC) as rn_quantity
	   ,SUM(sum_quantity) OVER (partition by product_id) as total_quantity
FROM level2),
level4 as(SELECT *
       ,SUM(sum_quantity) OVER (partition by product_id) as total_quantity_ohne_top_3
FROm level3
WHERE rn_quantity >= 4),
level5 as(SELECT *
       ,ROUND((total_quantity_ohne_top_3::numeric / total_quantity),4) as ratio
FROm level4)
SELECT *
FROM level5
WHERE ratio >= 0.6

-- 717. «Товар із хибним прискоренням»

WITH level1 as(SELECT product_id
	   ,order_date
	   ,quantity
	   ,ROW_NUMBER () OVER (partition by product_id order by order_date) as rn_date
	   ,COUNT(product_id) OVER (partition by product_id) as count_order
	   ,COUNT(product_id) OVER (partition by product_id) / 2 as middle_point 
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,case when rn_date <= middle_point THEN 'first'
	   when rn_date > middle_point THEN 'second'
	   END as halfs
	   ,SUM(quantity) OVER (partition by product_id) as total_quantity
FROM level1),
level3 as(SELECT DISTINCT product_id
       ,total_quantity
FROM level2),
level4 as(SELECT *
       ,ntile(4) OVER (order by total_quantity DESC) as ntile_quantity
FROM level3),
level5 as(SELECT *
FROm level2
JOIN level4 USING (product_id)
WHERE ntile_quantity = 4),
level6 as(SELECT product_id
       ,ROUND(AVG(quantity) FILTER (WHERE halfs = 'first')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(quantity) FILTER (WHERE halfs = 'second')::numeric,2) as avg_quantity_second
FROM level5
GROUP By product_id)
SELECT *
FROm level6
WHERE avg_quantity_second > avg_quantity_first

-- 718. «Товар із паразитним попитом»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id, order_id order by quantity DESC) as rn_product_in_order
	   ,SUM(quantity) OVER (partition by product_id) as total_quantity_product
FROM level1),
level3 as(SELECT *
       ,SUM(quantity) OVER (partition by product_id) as total_quantity_ohne_top_1
FROM level2
WHERE rn_product_in_order >= 2),
level4 as(SELECT *
       ,ROUND((total_quantity_ohne_top_1::numeric / total_quantity_product),4) as ratio
FROM level3)
SELECT *
FROM level4
WHERE ratio >= 0.65

-- 719. «Товар із ілюзією ширини»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT product_id
       ,COUNT(DISTINCT order_id) as count_order
FROM level1
GROUP By product_id),
level3 as(SELECT *
       ,ntile(4) OVER (order by count_order DESC) as ntile_count
FROM level2),
level4 as(SELECT *
FROM level1
JOIN level3 USING (product_id)),
level5 as(SELECT product_id
       ,percentile_cont(0.5) WITHIN GROUP (order by quantity) as median_quantity
FROM level4
GROUP By product_id),
level6 as(SELECT *
       ,NTILE(4) OVER (order by median_quantity DESC) as ntile_median
FROm level5)
SELECT *
FROM level4
JOIN level6 USING (product_id)
WHERE ntile_count = 1 AND ntile_median = 4