-- 808. «Індекс фальшивої різноманітності»

WITH level1 as(SELECT customer_id
	   ,COUNT(DISTINCT product_id) as count_unik_product
	   ,COUNT(product_id) as total_count_items_customer
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id)
SELECT *
       ,count_unik_product::numeric / total_count_items_customer::numeric as ratio
FROm level1
ORDER BY ratio

-- 809. «Індекс амнезії клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
       ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders),
level3 as(SELECT *
FROM level1
JOIN level2 USING (customer_id, order_id)
WHERE count_order >= 6),
level4 as(SELECT a.customer_id
       ,a.product_id as product_a
	   ,a.rn as rn_a
	   ,b.product_id as product_b
	   ,b.rn as rn_b
	   ,a.count_order
FROm level3 a
JOIN level3 b ON a.customer_id = b.customer_id
AND a.rn = b.rn - 1),
level5 as(SELECT *
       ,case when product_a <> product_b THEN 0 ELSE 1 END as flag_product 
FROm level4),
level6 as(SELECT *
       ,MAX(flag_product) OVER (partition by customer_id, rn_a) as max_flag_product_in_paar
FROM level5),
level7 as(SELECT DISTINCT customer_id
       ,rn_a
	   ,rn_b
	   ,count_order - 1 as real_count
	   ,max_flag_product_in_paar
FROm level6
ORDER BY customer_id),
level8 as(SELECT *
       ,sum(max_flag_product_in_paar) OVER (partition by customer_id) as sum_flag_product
FROm level7),
level9 as(SELECT *
       ,1 - (sum_flag_product::numeric / real_count::numeric) as amnesia_index
FROM level8)
SELECT DISTINCT customer_id
       ,amnesia_index
FROm level9
ORDER BY amnesia_index 

----- скрипт від Чатіка цієї ж задачі

WITH level1 AS (SELECT
       customer_id,
       order_id,
       LAG(order_id) OVER (PARTITION BY customer_id ORDER BY order_date) AS prev_order_id,
       COUNT(*) OVER (PARTITION BY customer_id) AS order_count
FROM orders),
level2 AS (SELECT *
FROM level1
WHERE prev_order_id IS NOT NULL
AND order_count >= 6)
SELECT customer_id
       ,AVG(CASE WHEN NOT EXISTS (
                   SELECT 1
                   FROM order_details d1
                   JOIN order_details d2
                     ON d1.product_id = d2.product_id
                    AND d1.order_id = level2.order_id
                    AND d2.order_id = level2.prev_order_id) THEN 1 ELSE 0 END) AS amnesia_index
FROM level2
GROUP BY customer_id
ORDER BY amnesia_index

-- 810. «Індекс розриву купівельної інерції»\

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
FROm level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,case when abs(sum_chek - prev_chek) > avg_chek THEN 1 ELSE 0 END as flag_chek
	   ,count_order - 1 as real_count
FROm level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level3),
level5 as(SELECT *
       ,ROUND((sum_flag_chek::numeric / real_count::numeric),4) as ratio
FROm level4)
SELECT DISTINCT customer_id
       ,ratio
FROM level5
ORDER BY ratio DESC

-- 811. «Індекс фантомної стабільності клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
FROm level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,abs(sum_chek - prev_chek) as abs_diff_chek
FROm level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,AVG(abs_diff_chek) OVER (partition by customer_id) as avg_abs_diff_chek
FROm level3),
level5 as(SELECT *
       ,avg_abs_diff_chek / avg_chek as psi
FROm level4)
SELECT DISTINCT customer_id
       ,psi
FROm level5
ORDER BY psi DESC

-- 812. «Індекс монополії клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,quantity
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,SUM(quantity) OVER (partition by customer_id) as total_quantity
	   ,SUM(quantity) OVER (partition by customer_id, product_id) as sum_quantity_per_product
FROm level1),
level3 as(SELECT DISTINCT customer_id
       ,product_id
	   ,sum_quantity_per_product
	   ,total_quantity
FROm level2
ORDER BY customer_id),
level4 as(SELECT *
       ,MAX(sum_quantity_per_product) OVER (partition by customer_id) as max_quantity_per_product
FROM level3),
level5 as(SELECT *
       ,max_quantity_per_product::numeric / total_quantity::numeric as ratio
FROm level4),
level6 as(SELECT DISTINCT customer_id
       ,max_quantity_per_product
	   ,total_quantity
	   ,ratio
FROM level5),
level7 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM orders
GROUP By customer_id)
SELECT *
FROm level6
JOIN level7 USING (customer_id)
WHERE count_order >= 6
ORDER BY ratio DESC

-- 813. «Індекс прихованого центру ваги клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
FROm level1
WHERE count_order >= 7),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level2
GROUP By customer_id),
level4 as(SELECT *
       ,case when sum_chek > median_chek THEN 1 ELSE 0 END as flag_chek
FROm level2
JOIN level3 USING (customer_id)),
level5 as(SELECT *
       ,AVG(flag_chek) OVER (partition by customer_id) as hidden_center_index
FROm level4),
level6 as(SELECT DISTINCT customer_id
       ,hidden_center_index
FROM level5),
level7 as(SELECT customer_id
       ,hidden_center_index
	   ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by hidden_center_index) FROM level6) as global_median_hci
FROM level6)
SELECT *
FROm level7
WHERE hidden_center_index > global_median_hci

-- 814. «Індекс перевернутого лідера клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
	   ,unit_price
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,SUM(quantity) OVER (partition by customer_id, product_id) as sum_quantity_product
	   ,AVG(unit_price) OVER (partition by customer_id, product_id) as avg_price_product
FROm level1),
level3 as(SELECT DISTINCT customer_id
       ,product_id
	   ,sum_quantity_product
	   ,avg_price_product
	   ,DENSE_RANK () OVER (partition by customer_id order by sum_quantity_product DESC) as rn_quantity
	   ,DENSE_RANK () OVER (partition by customer_id order by avg_price_product) as rn_price
FROm level2
ORDER BY customer_id),
level4 as(SELECT *
FROM level3
WHERE rn_quantity = 1 AND rn_price = 1),
level5 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM orders
GROUP By customer_id)
SELECT *
FROM level4
JOIN level5 USING (customer_id)
WHERE count_order >= 6

-- 815. «Індекс перевернутого середнього»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
FROm level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,case when sum_chek < avg_chek THEN 1 ELSE 0 END as flag_chek
FROm level2)
SELECT customer_id
       ,AVG(flag_chek) as reversed_mean_index
FROm level3
GROUP By customer_id
ORDER BY reversed_mean_index DESC

-- 816. «Індекс стрибка клієнта»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
FROm level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,max_chek / avg_chek as jump_index
FROM level2),
level4 as(SELECT DISTINCT customer_id
       ,jump_index
FROm level3),
level5 as(SELECT *
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by jump_index) FROM level4) as global_median_jump_index
FROM level4)
SELECT *
FROM level5
WHERE jump_index > global_median_jump_index
ORDER BY jump_index DESC
