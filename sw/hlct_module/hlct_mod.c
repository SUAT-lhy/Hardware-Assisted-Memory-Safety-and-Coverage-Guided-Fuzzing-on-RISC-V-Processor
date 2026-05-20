// hlct_mod.c — Linux kernel module for HLCT BRAM access
//
// Maps the 64 KB HLCT coverage BRAM physical range (AXI4-Lite at 0x7000_0000)
// into a character device /dev/hlct_bram.  AFL++ mmaps this device at startup
// to get a direct pointer to the coverage map — zero kernel involvement per
// coverage update, zero copy.
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/mm.h>
#include <linux/io.h>
#include <linux/uaccess.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("HAST-RV Authors");
MODULE_DESCRIPTION("HLCT coverage BRAM /dev/hlct_bram driver");

#define HLCT_BRAM_PHYS  0x70000000UL
#define HLCT_BRAM_SIZE  (64 * 1024)   /* 64 KB */
#define DEVICE_NAME     "hlct_bram"

static dev_t   hlct_dev;
static struct cdev hlct_cdev;
static struct class *hlct_class;

static int hlct_mmap(struct file *filp, struct vm_area_struct *vma)
{
    unsigned long size = vma->vm_end - vma->vm_start;
    unsigned long pfn  = HLCT_BRAM_PHYS >> PAGE_SHIFT;

    if (size > HLCT_BRAM_SIZE)
        return -EINVAL;

    vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);
    vma->vm_flags    |= VM_IO | VM_DONTEXPAND | VM_DONTDUMP;

    if (remap_pfn_range(vma, vma->vm_start, pfn, size, vma->vm_page_prot))
        return -EAGAIN;

    return 0;
}

static int hlct_open(struct inode *inode, struct file *filp)
{
    return 0;
}

static int hlct_release(struct inode *inode, struct file *filp)
{
    return 0;
}

static const struct file_operations hlct_fops = {
    .owner   = THIS_MODULE,
    .open    = hlct_open,
    .release = hlct_release,
    .mmap    = hlct_mmap,
};

static int __init hlct_init(void)
{
    int ret;

    ret = alloc_chrdev_region(&hlct_dev, 0, 1, DEVICE_NAME);
    if (ret < 0) {
        pr_err("hlct: alloc_chrdev_region failed: %d\n", ret);
        return ret;
    }

    cdev_init(&hlct_cdev, &hlct_fops);
    hlct_cdev.owner = THIS_MODULE;
    ret = cdev_add(&hlct_cdev, hlct_dev, 1);
    if (ret < 0) {
        unregister_chrdev_region(hlct_dev, 1);
        pr_err("hlct: cdev_add failed: %d\n", ret);
        return ret;
    }

    hlct_class = class_create(THIS_MODULE, DEVICE_NAME);
    if (IS_ERR(hlct_class)) {
        cdev_del(&hlct_cdev);
        unregister_chrdev_region(hlct_dev, 1);
        return PTR_ERR(hlct_class);
    }

    device_create(hlct_class, NULL, hlct_dev, NULL, DEVICE_NAME);
    pr_info("hlct: /dev/%s created, BRAM at 0x%08lx, size %d KB\n",
            DEVICE_NAME, HLCT_BRAM_PHYS, HLCT_BRAM_SIZE / 1024);
    return 0;
}

static void __exit hlct_exit(void)
{
    device_destroy(hlct_class, hlct_dev);
    class_destroy(hlct_class);
    cdev_del(&hlct_cdev);
    unregister_chrdev_region(hlct_dev, 1);
    pr_info("hlct: /dev/%s removed\n", DEVICE_NAME);
}

module_init(hlct_init);
module_exit(hlct_exit);
