-- 218. Знайди клієнтів, у яких різниця між будь-якими двома сусідніми замовленнями перевищує 180 днів, 
-- хоча загалом вони роблять ≥ 4 замовлення.

WITH level1 as(SELECT DISTINCT order_date
       ,customer_id
       ,order_id
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,COUNT(*) OVER (partition by customer_id) as count_order
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
FROM level1),
level3 as(SELECT *
       ,order_date - prev_date as diff
FROM level2),
level4 as(SELECT *
       ,case when diff > 180 THEN 1 ELSE 0 END flag_diff
	   ,count_order - 1 as count_real_order 
FROm level3),
level5 as(SELECT *
       ,SUM(flag_diff) OVER (partition by customer_id) as sum_flag_diff
FROM level4)
SELECT *
FROm level5
WHERE sum_flag_diff = count_real_order AND count_order >= 4

-- 219. Для кожного клієнта порахуй:
-- sum_quantity — загальну кількість товарів у замовленні
-- sum_check — суму чеку
-- Потім знайди тих клієнтів, де одночасно:
-- Замовлення з максимальною кількістю товарів → має мінімальний чек
-- Замовлення з мінімальною кількістю товарів → має максимальний чек 

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROW_number() OVER (partition by customer_id ORDER BY sum_chek DESC) as rank_chek
	   ,ROW_number() OVER (partition by customer_id ORDER BY sum_quantity DESC) as rank_quantity
	   ,COUNT(*) OVER (partition by customer_id) as count_order
FROM level1)
SELECT *
FROM level2
WHERE (rank_quantity = count_order AND rank_chek = 1) OR (rank_chek = count_order AND rank_quantity = 1)

-- 220. Деякі клієнти мають дивну поведінку:
-- За перші 3 замовлення у них кількість товару зростає (Q1 < Q2 < Q3).
-- Але при цьому сума чеку падає (C1 > C2 > C3).
-- Тобто тренди протилежні, причому на ранньому етапі життя клієнта.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id,order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVEr (partition by customer_id order by order_date) as rn
	   ,COUNT(*) OVER (partition by customer_id) as count_order
FROM level1),
level3 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_sum_quantity
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_sum_chek
FROM level2
WHERE rn <= 3 AND count_order >= 3),
level4 as(SELECT *
       ,case when prev_sum_quantity < sum_quantity THEN 1 ELSE 0 END as flag_quantity
	   ,case when prev_sum_chek > sum_chek THEN 1 else 0 END as flag_chek
FROM level3
WHERE prev_sum_chek is not null AND prev_sum_chek is not null),
level5 as(SELECT *
       ,SUM(flag_quantity) OVER (partition by customer_id) as sum_flag_quantity
	   ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROm level4)
SELECT *
FROM level5
WHERE sum_flag_quantity = 2 AND sum_flag_chek = 2 

-- 221. Деякі клієнти поводяться дивно:вони купують два різних типи товарів,
-- і всередині кожного типу вони поводяться стабільно, але між типами — абсолютно протилежно.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,category_name
	   ,SUM(quantity) as sum_quantity
FROM orders
JOIn order_details USING(order_id)
JOIN products USING(product_id)
JOIN categories USING(category_id)
GROUP BY customer_id,order_id,order_date,category_name
ORDER BY customer_id, sum_quantity DESC),
level2 as(SELECT *
       ,SUM(sum_quantity) OVER (partition by customer_id,category_name) as sum_qnt_per_category
FROM level1),
level3 as(SELECT *
       ,dense_rank() OVER (partition by customer_id order by sum_qnt_per_category DESC) as rank_qnt
FROM level2),
level4 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id, category_name ORDER by order_date) as prev_sum_quantity
FROM level3
WHERE rank_qnt <= 2),
level5 as(SELECT *
      ,case when sum_quantity > prev_sum_quantity AND rank_qnt = 1 THEN 1 else 0 END as flag_rank_1
	  ,case when prev_sum_quantity > sum_quantity AND rank_qnt = 2 THEN 1 else 0 END as flag_rank_2
FROM level4
WHERE prev_sum_quantity is not null),
level6 as(SELECT *
       ,SUM(flag_rank_1) OVER (partition by customer_id,rank_qnt) as sum_flag_rank_1
	   ,SUM(flag_rank_2) OVER (partition by customer_id,rank_qnt) as sum_flag_rank_2
	   ,COUNT(*) OVER (partition by customer_id, rank_qnt) as count_order_rank_1
	   ,COUNT(*) OVER (partition by customer_id, rank_qnt) as count_order_rank_2
FROM level5)
SELECT *
FROM level6
WHERE sum_flag_rank_1 = count_order_rank_1 AND sum_flag_rank_2 = count_order_rank_2

